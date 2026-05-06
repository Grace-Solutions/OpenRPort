# Container/Ui/Dockerfile
# Builds the openrport-ui (Nuxt 3) app from src/Ui.
# Multi-stage: build with Node, serve with minimal Node runtime.
#
# NUXT_API_URL and NUXT_APP_BASE_URL are injected at runtime via entrypoint.sh
# so the same image works for any deployment mode / URL.

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS builder

WORKDIR /app

# Copy UI source (subtree at src/Ui)
COPY src/Ui/ .

# Install with yarn (project uses yarn.lock)
RUN yarn install --frozen-lockfile

# Build the Nuxt app.
# NUXT_API_URL and NUXT_APP_BASE_URL can be overridden at build time if needed,
# but we prefer runtime injection – Nuxt 3 supports runtime env via useRuntimeConfig.
ARG NUXT_APP_BASE_URL=/ui
ARG NUXT_API_URL=http://localhost:8080
ENV NUXT_APP_BASE_URL=${NUXT_APP_BASE_URL}
ENV NUXT_API_URL=${NUXT_API_URL}

RUN yarn build

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nuxt && useradd -r -g nuxt nuxt

WORKDIR /app
COPY --from=builder /app/.output /app/.output

COPY Container/Ui/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

USER nuxt

ENV HOST=0.0.0.0
ENV PORT=3000
ENV NODE_ENV=production

ENTRYPOINT ["/entrypoint.sh"]
