# openrport-server

`rportd` (the OpenRPort server) packaged for the
[Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort) stack.
Renders `rportd.conf` from environment variables at startup, so the image is
fully self-contained — no repo checkout required to deploy.

## Tags

- `latest` &nbsp;— rolling, retagged on every push to `main` of the source repo
- `<short-sha>` &nbsp;— immutable, one tag per main-branch commit (use this in production)
- `vX.Y.Z`, `vX.Y` &nbsp;— published when the source repo cuts a release tag

## Ports (host networking)

| Port | Purpose |
|------|---------|
| `38100` | HTTP API (`/api/v1/*`) |
| `38101` | Chisel WebSocket (agent connect, HTTP Upgrade) |
| `38200-38400` | Reverse-tunnel pool (raw TCP listeners owned by `rportd`) |

The container is designed to run with `network_mode: host` so the entire
tunnel pool is reachable without enumerating port mappings.

## Required environment

| Variable | Notes |
|---|---|
| `RPORTD_API_USER` / `RPORTD_API_PASSWORD` | Basic auth admin credentials |
| `RPORTD_KEY_SEED` | Server identity seed (`openssl rand -hex 18`) |
| `RPORTD_JWT_SECRET` | API JWT signing key (`openssl rand -base64 50`) |
| `RPORTD_CLIENT_AUTH` | `clientID:secret` pair used by agents |
| `OPENRPORT_PAIRING_PUBLIC_URL` | External URL of the Pairing service |
| `OPENRPORT_SERVER_PUBLIC_URL` | External URL agents use to connect |

Optional: `OPENRPORT_TUNNEL_USED_PORTS`, `OPENRPORT_TUNNEL_HOST`,
`RPORT_OIDC_*` for SSO. The full list is documented in
[`.env.example`](https://github.com/Grace-Solutions/OpenRPort/blob/main/.env.example).

## Volumes

| Path | Purpose |
|------|---------|
| `/etc/rport` | Optional bind-mount; if `rportd.conf` exists it overrides env-rendered config |
| `/var/lib/rport` | Server data dir (clients DB, ACME state) |
| `/var/log/rport` | Log files |

## Quick start

The intended deployment is the full three-service stack via Compose:

```bash
git clone https://github.com/Grace-Solutions/OpenRPort
cd OpenRPort
cp .env.example .env   # then edit secrets
make prepare && make up
```

Or pull and run this image alone (renders config from env):

```bash
docker run -d --name openrport-server --network host \
  -e RPORTD_API_PASSWORD=... \
  -e RPORTD_KEY_SEED=... \
  -e RPORTD_JWT_SECRET=... \
  -e RPORTD_CLIENT_AUTH=clientauth1:secret \
  -v openrport-data:/var/lib/rport \
  gsoperator/openrport-server:latest
```

## Companion images

- [`gsoperator/openrport-pairing`](https://hub.docker.com/r/gsoperator/openrport-pairing) — installer/update endpoint + agent binary mirror
- [`gsoperator/openrport-ui`](https://hub.docker.com/r/gsoperator/openrport-ui) — Nuxt management UI

## Source

Built from [Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort)
(`Container/Server/Dockerfile`). Upstream:
[openrport/openrport](https://github.com/openrport/openrport).

## License

MPL-2.0 (inherits from upstream rportd).
