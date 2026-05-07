# OpenRPort

A unified Docker Compose stack that bundles the [`rportd`](https://github.com/openrport/openrport)
control plane, the [`rport-pairing`](https://github.com/openrport/rport-pairing) installer
service, and a Nuxt 3 web UI behind a single set of host ports. Drop-in fork
focused on operator ergonomics: one `.env`, one `make up`, one reverse-proxy
config — or pull the published images and run them with no repo at all.

## Highlights

- **Three first-class services**, all on `network_mode: host`:
  - `Server`  — `rportd` HTTP API + chisel agent listener
  - `Pairing` — `rport-pairing` installer-script renderer + static agent binary mirror
  - `UI`      — Nuxt 3 SSR frontend (login, clients, tags, tunnels, pairing wizard)
- **Self-contained images** — the Server and Pairing entrypoints render
  `rportd.conf` / `config.toml` from environment variables at startup, so you
  can deploy the published images without cloning this repo. A bind-mounted
  config still wins as an override.
- **OIDC built in** — the `rport-plus.so` plugin is compiled into the Server
  image. Set `RPORT_OIDC_ISSUER_URL` (+ client id/secret) and the entrypoint
  performs OIDC discovery against `/.well-known/openid-configuration` and
  writes the `[plus-plugin]` / `[plus-oauth]` blocks. Local login can be kept
  on as a break-glass via `RPORT_OIDC_ALLOW_LOCAL_LOGIN=true`.
- **Tag-aware client onboarding** — the UI persists tags through
  `POST /api/v1/clients-auth` so labels survive agent re-installs and show
  up in the rendered installer scripts.

## Endpoints (defaults)

All listeners bind to `${OPENRPORT_BIND_ADDRESS}` (default `0.0.0.0`; set to
`127.0.0.1` on a VPS where an edge reverse proxy is collocated).

| Port          | Service                                           |
| ------------- | ------------------------------------------------- |
| `38100`       | rportd HTTP API (`/api/v1/*`)                     |
| `38101`       | rportd chisel WebSocket (agent connect)           |
| `38102`       | rport-pairing + static agent binaries (`/binaries/*`) |
| `38103`       | Nuxt UI                                           |
| `38200-38400` | agent reverse-tunnel port pool (raw TCP, configurable) |

## Repository layout

```
Container/         Per-service Dockerfile + entrypoint.sh
  Server/          rportd image (builds rport-plus.so plugin into the runtime)
  Pairing/         rport-pairing image
  Ui/              Nuxt 3 image
  Binaries/        nginx mirror for agent installers (optional)
src/               Subtrees from upstream + local additions
  Server/          rportd source (cmd/rport, cmd/rportd, cmd/rport-plus-oidc)
  Pairing/         rport-pairing source
  Ui/              Nuxt 3 application source
scripts/           Host-side helpers (generate-config, fetch agent binaries, etc.)
docs/              COMPOSE-SPEC, ENV-SPEC, AgentHandoff, nginx.sample.conf
compose.yaml       Top-level stack
.env.example       Annotated environment template
```

## Quick start (repo-based)

```bash
git clone https://github.com/Grace-Solutions/OpenRPort.git
cd OpenRPort
cp .env.example .env
$EDITOR .env                      # rotate secrets, set OPENRPORT_*_PUBLIC_URL
make prepare                      # fetch agent binaries + render configs
make up                           # build + start
```

After `make up` completes, the API is reachable at
`http://<host>:38100/api/v1/login` (basic auth) and the UI at
`http://<host>:38103`. Place an HTTPS reverse proxy in front of the stack
using `docs/nginx.sample.conf` as a starting point.

## Standalone images (no repo required)

The Server and Pairing images render their full configuration from
environment variables on startup whenever no config file is bind-mounted.
The minimum env needed to boot the Server image alone is:

```bash
docker run -d --network host \
  -e RPORTD_KEY_SEED=$(openssl rand -hex 16) \
  -e RPORTD_CLIENT_AUTH=clientauth1:$(openssl rand -hex 16) \
  -e RPORTD_API_PASSWORD=$(openssl rand -hex 16) \
  -e RPORTD_JWT_SECRET=$(openssl rand -base64 50) \
  -e OPENRPORT_SERVER_PUBLIC_URL=https://rport.example.com \
  -e OPENRPORT_PAIRING_PUBLIC_URL=https://rport.example.com/pairing \
  openrport/server:local
```

Add OIDC by setting the issuer + client credentials — the entrypoint pulls
the discovery doc with `curl` + `jq` and wires up `[plus-plugin]` /
`[plus-oauth]` automatically:

```bash
  -e RPORT_OIDC_ISSUER_URL=https://idp.example.com/realms/rport \
  -e RPORT_OIDC_CLIENT_ID=rport \
  -e RPORT_OIDC_CLIENT_SECRET=... \
  -e RPORT_OIDC_REDIRECT_URI=https://rport.example.com/auth/callback \
  -e RPORT_OIDC_ALLOW_LOCAL_LOGIN=true
```

If `/.well-known/openid-configuration` is unreachable from the container,
supply the endpoints explicitly with `RPORT_OIDC_AUTHORIZE_URL`,
`RPORT_OIDC_TOKEN_URL`, and `RPORT_OIDC_JWKS_URL`.

## Authentication

`/api/v1/auth/provider` advertises which login surfaces are active:

| `auth_provider`  | Local login form | OIDC button |
| ---------------- | ---------------- | ----------- |
| `built-in`       | yes              | no          |
| `oidc`           | only when `allow_local_login=true` | yes |

The UI's `NUXT_PUBLIC_AUTH_MODE` (`auto` / `basic` / `oidc` / `both`)
overrides this per deployment when you want to force a single surface.

## Documentation

- `docs/COMPOSE-SPEC.md` — service / volume / network specification
- `docs/ENV-SPEC.md`     — every environment variable, grouped by service
- `docs/AgentHandoff.md` — operator runbook
- `docs/nginx.sample.conf` — reference edge reverse proxy

## Make targets

```
make help              # list all targets
make validate-env      # lint .env
make generate-config   # render Data/OpenRPort/.../{rportd.conf,config.toml}
make fetch-binaries    # pull official rport agent binaries
make build-agent       # build agent from src/Server for all targets
make prepare           # validate-env + generate-config + agent-binaries
make build             # docker compose build
make up                # build + docker compose up -d
make down              # docker compose down
make test              # run scripts/TestStack.sh
```

## License

GPL-3.0. See [`LICENSE`](LICENSE). Upstream `rportd`, `rport-pairing`, and
the rport web UI are licensed under their own terms; see the source trees
under `src/` for their respective LICENSE files.