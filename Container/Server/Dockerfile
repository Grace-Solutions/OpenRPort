# Container/Server/Dockerfile
# Builds the openrport server (rportd) from src/Server.
#
# Build context is the repo root so we can COPY src/ and Config/.
# Multi-stage: compile with Go, run on minimal Debian.

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.21-bookworm AS builder

WORKDIR /build

# Copy only the server source (subtree at src/Server)
COPY src/Server/ .

# Download deps (cached layer if go.sum unchanged)
RUN go mod download

# Build rportd. CGO is required because the source imports mattn/go-sqlite3
# (whose Error type and ErrConstraint/ErrBusy constants are cgo-gated). The
# upstream Makefile sets CGO_ENABLED=0 but doesn't actually compile cleanly;
# upstream releases are built via goreleaser which enables cgo.
RUN mkdir -p /out && \
    CGO_ENABLED=1 go build \
      -ldflags="-s -w" \
      -o /out/rportd \
      -v \
      ./cmd/rportd

# Build the open-source rport-plus OIDC plugin alongside rportd. Same Go
# version, same go.mod, same CGO setting -> guaranteed ABI compatibility
# when rportd loads it via plugin.Open at startup.
RUN CGO_ENABLED=1 go build \
      -buildmode=plugin \
      -o /out/rport-plus.so \
      ./cmd/rport-plus-oidc

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

# Runtime deps: ca-certificates for TLS, wget for healthcheck,
# curl + jq for OIDC discovery in entrypoint.sh when no config is mounted.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user and data directories
RUN groupadd -r rport && useradd -r -g rport -d /var/lib/rport rport && \
    mkdir -p /var/lib/rport /etc/rport && \
    chown -R rport:rport /var/lib/rport /etc/rport

COPY --from=builder /out/rportd /usr/local/bin/rportd
COPY --from=builder /out/rport-plus.so /usr/local/lib/rport/rport-plus.so

# Container/Server/entrypoint.sh handles header discovery + config mount
COPY Container/Server/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8081

USER rport

ENTRYPOINT ["/entrypoint.sh"]
