# Build from repository root: docker build -f examples/gpu/Dockerfile -t hf-gpu .
FROM python:3.12-slim-bookworm AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install torch==2.11.0 --index-url https://download.pytorch.org/whl/cu128  && pip install --no-cache-dir --prefix=/install -r requirements.txt
ENV PYTHONPATH=/install/lib/python3.12/site-packages
COPY scripts/download_model.py .
RUN python download_model.py
FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HF_HUB_OFFLINE=1     TRANSFORMERS_OFFLINE=1 MODEL_PATH=/opt/model HF_HOME=/tmp/huggingface MODEL_DEVICE=0
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid app --no-create-home app
COPY --from=build /install /usr/local
COPY --from=build /opt/model /opt/model
WORKDIR /app
COPY app ./app
USER 10001:10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log"]
