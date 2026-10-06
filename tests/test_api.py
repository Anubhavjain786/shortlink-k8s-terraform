import fakeredis
import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture()
def client():
    fake = fakeredis.FakeAsyncRedis(decode_responses=True)
    with TestClient(create_app(redis_client=fake), follow_redirects=False) as c:
        yield c


def test_health_and_ready(client):
    assert client.get("/healthz").json()["status"] == "ok"
    assert client.get("/readyz").json() == {"status": "ready"}


def test_create_then_redirect_counts_hits(client):
    created = client.post("/links", json={"url": "https://example.com/docs"})
    assert created.status_code == 201
    body = created.json()
    assert len(body["code"]) == 7
    assert body["short_url"].endswith("/" + body["code"])

    for _ in range(3):
        hop = client.get("/" + body["code"])
        assert hop.status_code == 307
        assert hop.headers["location"] == "https://example.com/docs"

    stats = client.get(f"/links/{body['code']}/stats").json()
    assert stats == {"code": body["code"], "url": "https://example.com/docs", "hits": 3}


def test_unknown_code_is_404(client):
    assert client.get("/nope123").status_code == 404
    assert client.get("/links/nope123/stats").status_code == 404


def test_rejects_invalid_url(client):
    assert client.post("/links", json={"url": "not-a-url"}).status_code == 422


def test_metrics_exposed(client):
    client.post("/links", json={"url": "https://example.com"})
    text = client.get("/metrics").text
    assert "shortlink_links_created_total" in text
    assert "shortlink_http_requests_total" in text


def test_codes_are_unique(client):
    codes = {client.post("/links", json={"url": "https://example.com"}).json()["code"] for _ in range(50)}
    assert len(codes) == 50
