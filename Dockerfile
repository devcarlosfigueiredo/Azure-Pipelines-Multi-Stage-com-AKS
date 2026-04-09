# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — Builder: install deps in isolated env
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# System deps for compiled packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — Runtime: minimal, non-root image
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL maintainer="devops@example.com" \
      org.opencontainers.image.title="azure-devops-demo" \
      org.opencontainers.image.description="Flask demo — Azure DevOps pipeline" \
      org.opencontainers.image.source="https://github.com/your-org/azure-devops-demo"

# Runtime deps only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Non-root user for security (AKS best practice)
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy application source
COPY app/ ./app/

# Build args injected by Azure Pipelines
ARG APP_VERSION=dev
ARG BUILD_ID=local
ARG BUILD_DATE=unknown

ENV APP_VERSION=${APP_VERSION} \
    BUILD_ID=${BUILD_ID} \
    BUILD_DATE=${BUILD_DATE} \
    ENVIRONMENT=production \
    PORT=8080 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8080

# Healthcheck used by Docker and AKS liveness probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Gunicorn — production WSGI server
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "2", \
     "--threads", "4", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--log-level", "info", \
     "app.main:app"]
