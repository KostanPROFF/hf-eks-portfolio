import asyncio
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from app import main


@pytest.fixture
def client(monkeypatch):
    classifier = Mock(return_value=[{"label": "POSITIVE", "score": 0.99}])
    monkeypatch.setattr(main, "load_model", lambda: classifier)
    with TestClient(main.app) as client:
        yield client, classifier


def test_predict_json_and_probes(client):
    api, model = client
    assert api.get("/health/live").status_code == 200
    assert api.get("/health/ready").status_code == 200
    response = api.post("/predict", json={"text": "Great service"})
    assert response.json() == {"label": "POSITIVE", "score": 0.99}
    model.assert_called_once_with("Great service", truncation=True, max_length=256)
    assert "inference_requests_total" in api.get("/metrics/").text


@pytest.mark.parametrize("body", [{}, {"text": ""}, {"text": "x" * 2001}])
def test_input_bounds(client, body):
    api, model = client
    assert api.post("/predict", json=body).status_code == 422
    model.assert_not_called()


def test_error_does_not_expose_internals(client):
    api, model = client
    model.side_effect = RuntimeError("private internal detail")
    response = api.post("/predict", json={"text": "hello"})
    assert response.status_code == 500
    assert response.json() == {"detail": "Inference failed"}
    model.side_effect = None
    model.return_value = [{"label": "NEGATIVE", "score": 0.9}]
    assert api.post("/predict", json={"text": "hello"}).status_code == 200


def test_not_ready(client):
    api, model = client
    main.app.state.ready = False
    assert api.get("/health/ready").status_code == 503
    assert api.post("/predict", json={"text": "hello"}).status_code == 503
    model.assert_not_called()


def test_queue_rejects_overload():
    async def scenario():
        main.app.state.ready = True
        main.app.state.slots = asyncio.Semaphore(0)
        with pytest.raises(main.HTTPException) as exc:
            await main.predict(main.PredictionRequest(text="hello"))
        assert exc.value.status_code == 429
    asyncio.run(scenario())
