# Container/Pairing/Dockerfile
# Builds the rport-pairing service from src/Pairing.
# Multi-stage: compile with Go, run on minimal Debian.

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.21-bookworm AS builder

WORKDIR /build

COPY src/Pairing/ .

RUN go mod download

# Entry point: cmd/rport-pairing.go (single-file main)
RUN set -x && \
    if [ -d "cmd" ]; then \
      MAIN=$(find cmd -name "*.go" | head -1) && \
      echo "Building from: $MAIN" && \
      go build -trimpath -ldflags="-s -w" -o /out/rport-pairing ./cmd/...; \
    else \
      go build -trimpath -ldflags="-s -w" -o /out/rport-pairing .; \
    fi

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rport-pairing && \
    useradd -r -g rport-pairing rport-pairing && \
    mkdir -p /etc/rport-pairing && \
    chown -R rport-pairing:rport-pairing /etc/rport-pairing

COPY --from=builder /out/rport-pairing /usr/local/bin/rport-pairing

COPY Container/Pairing/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9978

USER rport-pairing

ENTRYPOINT ["/entrypoint.sh"]
