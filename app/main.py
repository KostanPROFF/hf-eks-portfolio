import asyncio
import os
import time
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, make_asgi_app

REQUESTS = Counter("inference_requests_total", "Inference requests", ["outcome"])
LATENCY = Histogram("inference_duration_seconds", "Inference latency including queue time")
MODEL_PATH = os.getenv("MODEL_PATH", "/opt/model")


def load_model():
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer, pipeline
    torch.set_num_threads(int(os.getenv("TORCH_NUM_THREADS", "1")))
    model = AutoModelForSequenceClassification.from_pretrained(
        MODEL_PATH, local_files_only=True, trust_remote_code=False, use_safetensors=True)
    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_PATH, local_files_only=True, trust_remote_code=False)
    return pipeline("text-classification", model=model, tokenizer=tokenizer,
                    device=int(os.getenv("MODEL_DEVICE", "-1")))


@asynccontextmanager
async def lifespan(app):
    app.state.ready = False
    app.state.executor = ThreadPoolExecutor(max_workers=1)
    app.state.slots = asyncio.Semaphore(8)
    try:
        app.state.classifier = await asyncio.get_running_loop().run_in_executor(
            app.state.executor, load_model)
        app.state.ready = True
        yield
    finally:
        app.state.ready = False
        app.state.executor.shutdown(wait=True)


app = FastAPI(title="HF EKS Sentiment API", version="1.0.0", lifespan=lifespan)
app.mount("/metrics", make_asgi_app())


class PredictionRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class PredictionResponse(BaseModel):
    label: str
    score: float


@app.get("/health/live")
async def live():
    return {"status": "alive"}


@app.get("/health/ready")
async def ready():
    if not getattr(app.state, "ready", False):
        raise HTTPException(503, "Model is not ready")
    return {"status": "ready"}


@app.post("/predict", response_model=PredictionResponse)
async def predict(body: PredictionRequest):
    if not getattr(app.state, "ready", False):
        raise HTTPException(503, "Model is not ready")
    started = time.perf_counter()
    try:
        await asyncio.wait_for(app.state.slots.acquire(), timeout=0.05)
    except TimeoutError:
        REQUESTS.labels("overload").inc()
        raise HTTPException(429, "Inference queue full", headers={"Retry-After": "1"})
    try:
        result = await asyncio.get_running_loop().run_in_executor(
            app.state.executor,
            partial(app.state.classifier, body.text, truncation=True, max_length=256))
        REQUESTS.labels("success").inc()
        return result[0]
    except Exception:
        REQUESTS.labels("error").inc()
        raise HTTPException(500, "Inference failed") from None
    finally:
        app.state.slots.release()
        LATENCY.observe(time.perf_counter() - started)
