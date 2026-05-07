# openrport-ui

The OpenRPort management UI (Nuxt 3 / Vue 3) packaged for the
[Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort) stack.
A static Nuxt build served by Node, configured at runtime via env vars so a
single image deploys at any base path or against any API origin.

## Tags

- `latest` &nbsp;— rolling, retagged on every push to `main` of the source repo
- `<short-sha>` &nbsp;— immutable, one tag per main-branch commit (use this in production)
- `vX.Y.Z`, `vX.Y` &nbsp;— published when the source repo cuts a release tag

## Ports (host networking)

| Port | Purpose |
|------|---------|
| `38103` | Nuxt server (HTTP) |

Always front this with HTTPS at the edge (nginx, Caddy, Traefik, etc.).

## Required environment

| Variable | Notes |
|---|---|
| `NUXT_APP_BASE_URL` | Subpath the UI is mounted under (e.g. `/ui`); use `/` for root |
| `NUXT_PUBLIC_API_URL` | Full URL of the rportd API. Leave blank in subpath mode for relative URLs |
| `NUXT_PUBLIC_AUTH_MODE` | `auto`, `basic`, `oidc`, or `both` (default `both`) |
| `UI_INTERNAL_PORT` | Default `38103` |

Full reference:
[`.env.example`](https://github.com/Grace-Solutions/OpenRPort/blob/main/.env.example).

## Quick start

The intended deployment is the full three-service stack via Compose:

```bash
git clone https://github.com/Grace-Solutions/OpenRPort
cd OpenRPort
cp .env.example .env   # then edit secrets
make prepare && make up
```

Or pull and run this image alone:

```bash
docker run -d --name openrport-ui --network host \
  -e NUXT_APP_BASE_URL=/ui \
  -e NUXT_PUBLIC_API_URL=https://rport.example.com \
  -e NUXT_PUBLIC_AUTH_MODE=both \
  gsoperator/openrport-ui:latest
```

## Companion images

- [`gsoperator/openrport-server`](https://hub.docker.com/r/gsoperator/openrport-server) — `rportd` API + chisel control plane + tunnel pool
- [`gsoperator/openrport-pairing`](https://hub.docker.com/r/gsoperator/openrport-pairing) — installer/update endpoint + agent binary mirror

## Source

Built from [Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort)
(`Container/Ui/Dockerfile`). Upstream UI:
[openrport/rport-frontend](https://github.com/openrport/rport-frontend).

## License

MPL-2.0 (inherits from upstream rport-frontend).
