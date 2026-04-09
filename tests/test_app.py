"""
Test suite — Azure DevOps Demo
Covers unit tests + integration / smoke-test helpers.
"""
import os
import pytest

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("APP_VERSION", "0.0.0-test")
os.environ.setdefault("BUILD_ID", "test-build")

# Import after env vars are set
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


# ── / ────────────────────────────────────────────────────────────────────────
class TestIndex:
    def test_returns_200(self, client):
        resp = client.get("/")
        assert resp.status_code == 200

    def test_contains_app_name(self, client):
        data = client.get("/").get_json()
        assert data["app"] == "azure-devops-demo"

    def test_contains_version(self, client):
        data = client.get("/").get_json()
        assert "version" in data

    def test_contains_environment(self, client):
        data = client.get("/").get_json()
        assert data["environment"] == "test"


# ── /health ──────────────────────────────────────────────────────────────────
class TestHealth:
    def test_returns_200(self, client):
        assert client.get("/health").status_code == 200

    def test_status_healthy(self, client):
        data = client.get("/health").get_json()
        assert data["status"] == "healthy"

    def test_has_timestamp(self, client):
        data = client.get("/health").get_json()
        assert "timestamp" in data


# ── /ready ───────────────────────────────────────────────────────────────────
class TestReady:
    def test_returns_200(self, client):
        assert client.get("/ready").status_code == 200

    def test_status_ready(self, client):
        data = client.get("/ready").get_json()
        assert data["status"] == "ready"

    def test_has_uptime(self, client):
        data = client.get("/ready").get_json()
        assert "uptime_seconds" in data
        assert isinstance(data["uptime_seconds"], float)


# ── /info ────────────────────────────────────────────────────────────────────
class TestInfo:
    def test_returns_200(self, client):
        assert client.get("/info").status_code == 200

    def test_build_id_present(self, client):
        data = client.get("/info").get_json()
        assert data["build_id"] == "test-build"


# ── /metrics ─────────────────────────────────────────────────────────────────
class TestMetrics:
    def test_returns_200(self, client):
        assert client.get("/metrics").status_code == 200

    def test_content_type_prometheus(self, client):
        resp = client.get("/metrics")
        assert "text/plain" in resp.content_type

    def test_contains_uptime_metric(self, client):
        resp = client.get("/metrics")
        assert b"app_uptime_seconds" in resp.data

    def test_contains_app_info(self, client):
        resp = client.get("/metrics")
        assert b"app_info" in resp.data


# ── Error handlers ───────────────────────────────────────────────────────────
class TestErrors:
    def test_404_json(self, client):
        resp = client.get("/nonexistent-route")
        assert resp.status_code == 404
        data = resp.get_json()
        assert data["error"] == "Not found"
