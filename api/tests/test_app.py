from __future__ import annotations

from fastapi.testclient import TestClient

from capsa.app import create_app


def test_health():
    client = TestClient(create_app())
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_openapi_is_under_api_prefix():
    client = TestClient(create_app())
    assert client.get("/api/v1/openapi.json").status_code == 200
    assert client.get("/openapi.json").status_code == 404
