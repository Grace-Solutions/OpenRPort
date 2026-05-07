# OpenRPort

A Docker Compose stack that bundles three services behind a single host
networking namespace: **Server** (`rportd` control plane + chisel agent
listener), **Pairing** (`rport-pairing` installer-script renderer + static
agent binary mirror), and **UI** (web frontend). This README focuses on
deployment — how to map the stack to a single subpath, three subdomains,
direct ports, or a standalone `docker run`, and how to tune ports, bind
addresses, the agent connect URL, and the reverse-tunnel pool to fit your
network.

## Services and default ports

`compose.yaml` runs every service with `network_mode: host`. Each one
binds directly on the host's network namespace — no NAT, no docker-proxy,
no published-port indirection. All ports below are overridable in `.env`.

| Service | Port (env var)                                | Purpose                                             |
| ------- | --------------------------------------------- | --------------------------------------------------- |
| Server  | `38100` (`SERVER_API_INTERNAL_PORT`)          | rportd HTTP API (`/api/v1/*`)                       |
| Server  | `38101` (`SERVER_CLIENT_INTERNAL_PORT`)       | rportd chisel WS (agent connect, HTTP Upgrade)      |
| Pairing | `38102` (`PAIRING_INTERNAL_PORT`)             | pairing endpoints + static binaries (`/binaries/*`) |
| UI      | `38103` (`UI_INTERNAL_PORT`)                  | web frontend                                        |
| Server  | `38200-38400` (`OPENRPORT_TUNNEL_USED_PORTS`) | agent reverse-tunnel pool (raw TCP)                 |

The 38000-band defaults sit clear of common host services (8080, 3000,
9978, etc.). All five ranges can be moved freely.

## Configuration knobs

Every lever below lives in `.env`. See [`.env.example`](.env.example) for
the complete annotated set; the variables that decide the deployment
shape are summarized here.

### Bind address

```env
# Default for all services (each can be overridden individually).
OPENRPORT_BIND_ADDRESS=0.0.0.0

# Per-service overrides (leave blank to inherit OPENRPORT_BIND_ADDRESS):
OPENRPORT_SERVER_API_BIND_ADDRESS=
OPENRPORT_SERVER_CLIENT_BIND_ADDRESS=
OPENRPORT_PAIRING_BIND_ADDRESS=
OPENRPORT_UI_BIND_ADDRESS=
```

- `0.0.0.0` — dedicated stack host; agents and browsers reach the host's
  IP directly.
- `127.0.0.1` — VPS where an edge reverse proxy (nginx, caddy, traefik)
  on the same host fronts the stack; only the proxy talks to the
  containers.
- Mix and match per service, e.g. chisel listener on the public IP, API
  and UI on loopback only.

> The agent reverse-tunnel pool always binds to whatever
> `OPENRPORT_SERVER_CLIENT_BIND_ADDRESS` resolves to, because that is the
> address rportd listens on for the chisel control channel. Keep that
> address reachable from the agent network (or via your edge proxy).

### Ports and the tunnel pool

```env
SERVER_API_INTERNAL_PORT=38100
SERVER_CLIENT_INTERNAL_PORT=38101
PAIRING_INTERNAL_PORT=38102
UI_INTERNAL_PORT=38103

OPENRPORT_TUNNEL_USED_PORTS=38200-38400
OPENRPORT_TUNNEL_EXCLUDED_PORTS=1-1024
```

`OPENRPORT_TUNNEL_USED_PORTS` is the range rportd allocates from when an
agent requests a reverse tunnel; `_EXCLUDED_PORTS` carves holes inside
it. Both accept ports, ranges, or a comma-separated mix
(`38200,38205,38300-38400`). Move the whole pool by setting both env
vars together (e.g. `40000-40500` paired with whatever firewall opening
you allow).

### Public URLs (what agents and browsers hit)

```env
OPENRPORT_SERVER_PUBLIC_URL=         # agent connect URL (chisel)
OPENRPORT_SERVER_API_URL=            # browser-facing REST API URL
OPENRPORT_PAIRING_PUBLIC_URL=        # pairing endpoints
OPENRPORT_UI_PUBLIC_URL=             # web UI
OPENRPORT_BINARIES_PUBLIC_URL=       # static agent binaries
```

`OPENRPORT_SERVER_PUBLIC_URL` is the most consequential — it is baked
into rendered installer scripts, so this is the URL every agent uses to
phone home. Once agents are out in the field, changing it means
re-issuing installers (or migrating with `--server <new>`).

`OPENRPORT_SERVER_API_URL` is what the UI fetches the REST API from in
the browser. In subpath mode behind a single edge it can be left blank
(the UI uses a relative URL on its own origin); in subdomain or
split-port modes set it to the absolute API URL.

### Required ports inbound from the internet

| Direction        | Port(s)                  | Why                                                                         |
| ---------------- | ------------------------ | --------------------------------------------------------------------------- |
| Agents → Server  | chisel WS port (or 443)  | Agent control channel. Either a direct TCP port or via your reverse proxy. |
| Operators → UI   | UI port (or 443)         | Browser access, typically through TLS on the edge proxy.                   |
| Operators → API  | API port (or 443)        | UI fetches the REST API; same edge in subpath mode.                        |
| Operators → Pairing | Pairing port (or 443) | Install-script rendering during onboarding.                                |
| Tunnel consumers → Server | tunnel pool ports | Inbound TCP for whatever services the agents expose back through reverse tunnels. |

The tunnel pool ports are raw TCP — they do **not** go through the
reverse proxy. Forward / firewall the entire range
(`OPENRPORT_TUNNEL_USED_PORTS`) directly to the stack host on whichever
interface `OPENRPORT_SERVER_CLIENT_BIND_ADDRESS` resolves to.

## Deployment scenarios

The Server and Pairing images render their config from environment variables
on startup whenever `/etc/rport/rportd.conf` and
`/etc/rport-pairing/config.toml` are not bind-mounted, so each scenario
below works either with the repo (`docker compose up -d`) or with the
published images alone (`docker run` / Kubernetes / Nomad).

### Scenario A — Subpath behind one domain

A single hostname fronts everything. Most common production setup.

```env
OPENRPORT_DEPLOYMENT_MODE=subpath
OPENRPORT_BIND_ADDRESS=127.0.0.1                       # edge proxy is collocated
OPENRPORT_SERVER_PUBLIC_URL=https://rport.example.com
OPENRPORT_SERVER_API_URL=                              # blank → UI uses relative URL
OPENRPORT_UI_PUBLIC_URL=https://rport.example.com/ui
OPENRPORT_PAIRING_PUBLIC_URL=https://rport.example.com/pairing
OPENRPORT_BINARIES_PUBLIC_URL=https://rport.example.com/binaries
```

Edge nginx routes by prefix; the chisel agent connect lives at the root
(catch-all):

```nginx
location /api/      { proxy_pass http://127.0.0.1:38100; }
location /ui/       { proxy_pass http://127.0.0.1:38103;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection $connection_upgrade; }
location /pairing/  { proxy_pass http://127.0.0.1:38102/; }
location /binaries/ { proxy_pass http://127.0.0.1:38102; }
location /          { proxy_pass http://127.0.0.1:38101;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection $connection_upgrade; }
```

Full reference: [`docs/nginx.sample.conf`](docs/nginx.sample.conf).

Inbound firewall: `443` only.

### Scenario B — Three subdomains

Each service lives on its own DNS name. Useful when you want separate TLS
certs, separate access logs, or a dedicated `chisel.` host that's WAN-open
while the UI/API stay behind a SSO mesh.

```env
OPENRPORT_DEPLOYMENT_MODE=dns
OPENRPORT_BIND_ADDRESS=127.0.0.1
OPENRPORT_SERVER_PUBLIC_URL=https://chisel.rport.example.com
OPENRPORT_SERVER_API_URL=https://api.rport.example.com
OPENRPORT_UI_PUBLIC_URL=https://ui.rport.example.com
OPENRPORT_PAIRING_PUBLIC_URL=https://pairing.rport.example.com
OPENRPORT_BINARIES_PUBLIC_URL=https://pairing.rport.example.com/binaries

# Subpath vars are ignored in dns mode, but harmless to leave blank.
OPENRPORT_SERVER_BASE_PATH=/
OPENRPORT_PAIRING_BASE_PATH=/
OPENRPORT_UI_BASE_PATH=/
OPENRPORT_BINARIES_BASE_PATH=/binaries
```

Edge nginx (one `server{}` per subdomain, all forwarding to loopback):

```nginx
server { server_name api.rport.example.com;     location / { proxy_pass http://127.0.0.1:38100; } }
server { server_name ui.rport.example.com;      location / { proxy_pass http://127.0.0.1:38103;
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection $connection_upgrade; } }
server { server_name pairing.rport.example.com; location / { proxy_pass http://127.0.0.1:38102; } }
server { server_name chisel.rport.example.com;  location / { proxy_pass http://127.0.0.1:38101;
        proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection $connection_upgrade; } }
```

Inbound firewall: `443` only (chisel rides HTTPS via WS Upgrade on the
`chisel.` vhost).

### Scenario C — Direct port access (no reverse proxy)

Lab, VPN-only, or air-gapped deployments. Agents and operators talk to
the host on the per-service ports directly; no TLS termination unless you
add it externally.

```env
OPENRPORT_DEPLOYMENT_MODE=local
OPENRPORT_BIND_ADDRESS=0.0.0.0
OPENRPORT_SERVER_PUBLIC_URL=http://10.0.0.5:38101
OPENRPORT_SERVER_API_URL=http://10.0.0.5:38100
OPENRPORT_UI_PUBLIC_URL=http://10.0.0.5:38103
OPENRPORT_PAIRING_PUBLIC_URL=http://10.0.0.5:38102
OPENRPORT_BINARIES_PUBLIC_URL=http://10.0.0.5:38102/binaries
```

Inbound firewall: `38100, 38101, 38102, 38103, 38200-38400` (or whatever
you've moved each to via the port env vars). The four service ports plus
the entire tunnel pool.

### Scenario D — Standalone images (no repo)

Pull the images and run them anywhere. The entrypoints render the full
config from environment variables; nothing needs to be bind-mounted.

```bash
docker run -d --network host --name openrport-server \
  -e RPORTD_KEY_SEED=$(openssl rand -hex 16) \
  -e RPORTD_CLIENT_AUTH=clientauth1:$(openssl rand -hex 16) \
  -e RPORTD_API_PASSWORD=$(openssl rand -hex 16) \
  -e RPORTD_JWT_SECRET=$(openssl rand -base64 50) \
  -e OPENRPORT_BIND_ADDRESS=0.0.0.0 \
  -e SERVER_API_INTERNAL_PORT=38100 \
  -e SERVER_CLIENT_INTERNAL_PORT=38101 \
  -e OPENRPORT_TUNNEL_USED_PORTS=38200-38400 \
  -e OPENRPORT_SERVER_PUBLIC_URL=https://rport.example.com \
  -e OPENRPORT_PAIRING_PUBLIC_URL=https://rport.example.com/pairing \
  openrport/server:local

docker run -d --network host --name openrport-pairing \
  -e PAIRING_INTERNAL_PORT=38102 \
  -e OPENRPORT_PAIRING_PUBLIC_URL=https://rport.example.com/pairing \
  -e OPENRPORT_PAIRING_DOWNLOADS_BINARIES_BASE_URL=https://rport.example.com/binaries \
  openrport/pairing:local
```

A bind-mounted `/etc/rport/rportd.conf` (or
`/etc/rport-pairing/config.toml`) wins over the env-driven render when
present, so existing operator workflows continue to work unchanged.

## Agent install

Once the stack is reachable at `OPENRPORT_PAIRING_PUBLIC_URL`, generate a
pairing code from the UI (or `POST /api/v1/clients-auth` directly) and
hand it to a target host:

```bash
# Linux / macOS
curl -s https://rport.example.com/pairing/<7-char-code> | sh

# Windows (PowerShell)
iwr -useb https://rport.example.com/pairing/<7-char-code> | iex
```

The rendered installer bakes in `OPENRPORT_SERVER_PUBLIC_URL` as the
chisel target and pulls the agent binary from
`OPENRPORT_PAIRING_DOWNLOADS_BINARIES_BASE_URL` (falling back to upstream
`download.openrport.io` when blank).

## OIDC single sign-on

The Server image ships with the `rport-plus.so` plugin compiled in. Set
the issuer + client credentials and the entrypoint discovers the OIDC
endpoints at startup:

```env
RPORT_OIDC_ISSUER_URL=https://idp.example.com/realms/rport
RPORT_OIDC_CLIENT_ID=rport
RPORT_OIDC_CLIENT_SECRET=...
RPORT_OIDC_REDIRECT_URI=https://rport.example.com/auth/callback
RPORT_OIDC_ALLOW_LOCAL_LOGIN=true   # keep admin/<pass> as break-glass
```

If `/.well-known/openid-configuration` is unreachable from the container,
supply the endpoints explicitly with `RPORT_OIDC_AUTHORIZE_URL`,
`RPORT_OIDC_TOKEN_URL`, and `RPORT_OIDC_JWKS_URL`. The UI reads
`/api/v1/auth/provider` to decide which login surfaces to render; force a
specific surface per deployment with `OPENRPORT_UI_AUTH_MODE`
(`auto` / `basic` / `oidc` / `both`).

## Documentation

- [`.env.example`](.env.example) — every environment variable, annotated
- [`docs/COMPOSE-SPEC.md`](docs/COMPOSE-SPEC.md) — service / volume / network specification
- [`docs/ENV-SPEC.md`](docs/ENV-SPEC.md) — env-var reference grouped by service
- [`docs/AgentHandoff.md`](docs/AgentHandoff.md) — operator runbook
- [`docs/nginx.sample.conf`](docs/nginx.sample.conf) — reference edge reverse proxy

## License

GPL-3.0. See [`LICENSE`](LICENSE). Upstream `rportd`, `rport-pairing`, and
the rport web UI are licensed under their own terms; see the source trees
under `src/` for their respective LICENSE files.
