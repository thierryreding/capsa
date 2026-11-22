from __future__ import annotations


def test_health(api):
    response = api.client().get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_openapi_is_under_api_prefix(api):
    client = api.client()
    assert client.get("/api/v1/openapi.json").status_code == 200
    assert client.get("/openapi.json").status_code == 404


def test_unsafe_methods_need_csrf_header(api):
    client = api.client()
    client.headers.pop("X-Capsa-CSRF")
    r = client.post("/api/v1/auth/logout")
    assert r.status_code == 403
    assert "X-Capsa-CSRF" in r.json()["detail"]
    assert client.get("/api/v1/health").status_code == 200
