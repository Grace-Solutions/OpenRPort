# openrport-pairing

`rport-pairing` packaged for the
[Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort) stack.
Hosts one-shot installer URLs for new agents and serves the static agent
binaries that the rendered installer scripts download. Config is rendered
from environment variables at startup.

## Tags

- `latest` &nbsp;— rolling, retagged on every push to `main` of the source repo
- `<short-sha>` &nbsp;— immutable, one tag per main-branch commit (use this in production)
- `vX.Y.Z`, `vX.Y` &nbsp;— published when the source repo cuts a release tag

## Ports (host networking)

| Port | Purpose |
|------|---------|
| `38102` | Pairing HTTP endpoint (`POST /`, `GET /<code>`, `GET /update`) + static binaries under `${RPORT_PAIRING_BINARIES_PATH}` |

## Required environment

| Variable | Notes |
|---|---|
| `OPENRPORT_PAIRING_PUBLIC_URL` | External URL the rendered installer scripts point at |
| `OPENRPORT_SERVER_PUBLIC_URL` | URL agents connect to after install |
| `PAIRING_INTERNAL_PORT` | Default `38102` |

Optional: `RPORT_PAIRING_BINARIES_DIR` / `RPORT_PAIRING_BINARIES_PATH`
to expose a directory of pre-fetched agent artefacts at a custom path,
and `OPENRPORT_PAIRING_DOWNLOADS_*` to override the URLs baked into the
rendered installer/update scripts. Full reference:
[`.env.example`](https://github.com/Grace-Solutions/OpenRPort/blob/main/.env.example).

## Volumes

| Path | Purpose |
|------|---------|
| `/etc/rport-pairing` | Optional bind-mount; if `config.toml` exists it overrides env-rendered config |
| `/usr/share/rport-pairing/binaries` | Read-only mount of fetched agent artefacts (zip + signature) |
| `/var/log/rport-pairing` | Log files |

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
docker run -d --name openrport-pairing --network host \
  -e OPENRPORT_PAIRING_PUBLIC_URL=https://rport.example.com/pairing \
  -e OPENRPORT_SERVER_PUBLIC_URL=https://rport.example.com \
  -v /srv/openrport/binaries:/usr/share/rport-pairing/binaries:ro \
  gsoperator/openrport-pairing:latest
```

## Companion images

- [`gsoperator/openrport-server`](https://hub.docker.com/r/gsoperator/openrport-server) — `rportd` API + chisel control plane + tunnel pool
- [`gsoperator/openrport-ui`](https://hub.docker.com/r/gsoperator/openrport-ui) — Nuxt management UI

## Source

Built from [Grace-Solutions/OpenRPort](https://github.com/Grace-Solutions/OpenRPort)
(`Container/Pairing/Dockerfile`). Upstream:
[openrport/openrport-pairing](https://github.com/openrport/openrport-pairing).

## License

MPL-2.0 (inherits from upstream rport-pairing).
