"""
Azure DevOps Demo - Flask Application
Production-grade API with health checks and observability
"""
import os
import time
import logging
from datetime import datetime
from flask import Flask, jsonify, request

# ── Logging ─────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)

# ── App ──────────────────────────────────────────────────────────────────────
app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
BUILD_ID    = os.getenv("BUILD_ID", "local")
START_TIME  = time.time()


# ── Routes ───────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return jsonify({
        "app": "azure-devops-demo",
        "version": APP_VERSION,
        "environment": ENVIRONMENT,
        "build_id": BUILD_ID,
        "message": "🚀 Deployed via Azure Pipelines → AKS",
    })


@app.route("/health")
def health():
    """Liveness probe — used by Kubernetes and pipeline smoke tests."""
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()})


@app.route("/ready")
def ready():
    """Readiness probe — signals the pod is ready to receive traffic."""
    uptime = round(time.time() - START_TIME, 2)
    return jsonify({
        "status": "ready",
        "uptime_seconds": uptime,
        "environment": ENVIRONMENT,
    })


@app.route("/info")
def info():
    """Detailed build & runtime information — useful for release validation."""
    return jsonify({
        "version": APP_VERSION,
        "build_id": BUILD_ID,
        "environment": ENVIRONMENT,
        "python_version": os.popen("python3 --version").read().strip(),
        "hostname": os.uname().nodename,
    })


@app.route("/metrics")
def metrics():
    """Basic Prometheus-style metrics endpoint (extend with prometheus_client)."""
    uptime = round(time.time() - START_TIME, 2)
    return (
        f"# HELP app_uptime_seconds Application uptime\n"
        f"# TYPE app_uptime_seconds gauge\n"
        f'app_uptime_seconds{{env="{ENVIRONMENT}"}} {uptime}\n'
        f"# HELP app_info Application build information\n"
        f"# TYPE app_info gauge\n"
        f'app_info{{version="{APP_VERSION}",build_id="{BUILD_ID}",env="{ENVIRONMENT}"}} 1\n'
    ), 200, {"Content-Type": "text/plain; version=0.0.4"}


# ── Error handlers ───────────────────────────────────────────────────────────
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not found", "path": request.path}), 404


@app.errorhandler(500)
def server_error(e):
    logger.exception("Internal server error")
    return jsonify({"error": "Internal server error"}), 500


# ── Entry point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    logger.info(f"Starting {ENVIRONMENT} server on port {port} — v{APP_VERSION}")
    app.run(host="0.0.0.0", port=port, debug=(ENVIRONMENT == "development"))
