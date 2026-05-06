# Container/Pairing/Dockerfile
# Builds the rport-pairing service from src/Pairing.
# Multi-stage: compile with Go, run on minimal Debian.

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.21-bookworm AS builder

WORKDIR /build

COPY src/Pairing/ .

RUN go mod download

# Build rport-pairing – entry point is cmd/rport-pairing.go
RUN mkdir -p /out && \
    CGO_ENABLED=0 go build \
      -ldflags="-s -w" \
      -o /out/rport-pairing \
      -v \
      ./cmd/rport-pairing.go

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rport-pairing && \
    useradd -r -g rport-pairing rport-pairing && \
    mkdir -p /etc/rport-pairing /usr/share/rport-pairing/binaries && \
    chown -R rport-pairing:rport-pairing /etc/rport-pairing /usr/share/rport-pairing

COPY --from=builder /out/rport-pairing /usr/local/bin/rport-pairing

COPY Container/Pairing/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9978

USER rport-pairing

ENTRYPOINT ["/entrypoint.sh"]
