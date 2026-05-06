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

# Build rportd (main entry point is cmd/rportd/main.go or cmd/rportd/)
# We discover the correct path from the module's cmd directory.
RUN set -x && \
    if [ -d "cmd/rportd" ]; then \
      go build -trimpath -ldflags="-s -w" -o /out/rportd ./cmd/rportd; \
    elif [ -f "cmd/rportd.go" ]; then \
      go build -trimpath -ldflags="-s -w" -o /out/rportd ./cmd/rportd.go; \
    else \
      echo "Searching for main package..." && \
      MAIN_PKG=$(grep -rl 'func main()' cmd/ | head -1 | xargs dirname) && \
      go build -trimpath -ldflags="-s -w" -o /out/rportd "./${MAIN_PKG}"; \
    fi

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

# Runtime deps: ca-certificates for TLS, wget for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user and data directories
RUN groupadd -r rport && useradd -r -g rport -d /var/lib/rport rport && \
    mkdir -p /var/lib/rport /etc/rport && \
    chown -R rport:rport /var/lib/rport /etc/rport

COPY --from=builder /out/rportd /usr/local/bin/rportd

# Container/Server/entrypoint.sh handles header discovery + config mount
COPY Container/Server/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8081

USER rport

ENTRYPOINT ["/entrypoint.sh"]
