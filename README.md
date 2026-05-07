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
OPENRPORT_SERVER_PUBLIC_URL=         # agent connect URL (chisel WS)
OPENRPORT_SERVER_API_URL=            # browser-facing REST API URL
OPENRPORT_PAIRING_PUBLIC_URL=        # pairing endpoints
OPENRPORT_UI_PUBLIC_URL=             # web UI
OPENRPORT_BINARIES_PUBLIC_URL=       # static agent binaries
OPENRPORT_TUNNEL_HOST=               # hostname/IP for tunnel link generation
```

`OPENRPORT_SERVER_API_URL` is what the UI fetches the REST API from in
the browser. In subpath mode behind a single edge it can be left blank
(the UI uses a relative URL on its own origin); in subdomain or
split-port modes set it to the absolute API URL.

`OPENRPORT_TUNNEL_HOST` controls the host part of the URLs rportd shows
operators when a tunnel is running. Set it whenever the API/UI sits
behind an L7 reverse proxy (nginx, Traefik, Caddy) that cannot forward
raw TCP/UDP — the tunnel ports are raw TCP and bypass the proxy, so
their links must point at a hostname/IP that maps directly to the stack
host on whichever interface `OPENRPORT_SERVER_CLIENT_BIND_ADDRESS`
resolves to.

### Agent connect URL (how it is defined and threaded)

The "agent connect URL" — the URL every agent uses to phone home — is
`OPENRPORT_SERVER_PUBLIC_URL`. It is the most consequential single
setting in the stack because it is baked into every rendered installer
script; once agents are deployed, changing it means re-issuing installers
(or running `rport --server <new>` on each host).

The chain it travels through:

```
.env
  OPENRPORT_SERVER_PUBLIC_URL=https://rport.example.com
        │
        ▼  Container/Server/entrypoint.sh
rportd.conf
  [server] url = "https://rport.example.com"
        │
        ▼  rportd creates a pairing deposit when an operator
        │  POSTs /api/v1/clients-auth (or clicks "Add client" in UI)
        │  → deposit.ConnectUrl = <[server] url>
        │
        ▼  rport-pairing stores the deposit under a 7-char code
        │  and renders it into install scripts on demand
linux  installer_vars.sh : CONNECT_URL="https://rport.example.com"
windows vars.ps1         : $connect_url = "https://rport.example.com"
        │
        ▼  install scripts write rport.conf on the agent host
agent rport.conf
  [client] server = "https://rport.example.com"
```

Every link in this chain is automatic: set
`OPENRPORT_SERVER_PUBLIC_URL` once and rportd, the pairing service, and
every rendered installer agree on it. The other public URLs travel
through their own direct paths: `OPENRPORT_PAIRING_PUBLIC_URL` →
`config.toml` `[server] url`; `OPENRPORT_TUNNEL_HOST` → `rportd.conf`
`[server] tunnel_host`; the binary-download URLs →
`config.toml` `[downloads]` → installer vars
(`BINARIES_BASE_URL` / `$binaries_base_url`).

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

## Connection flow

Two flows matter: how an agent gets installed and connected (control
plane), and how an operator reaches a service running behind that agent
(data plane). Sample IPs are illustrative — substitute your own.

### 1. Onboarding and agent control channel

```
   ┌───────────────────────┐                         ┌──────────────────────────┐
   │ Operator browser      │ 1. open UI / create     │ Edge firewall + reverse  │
   │ 198.51.100.10         │    pairing code         │ proxy (nginx/Traefik)    │
   │                       │ ───────────────────────▶│ 203.0.113.20  :443       │
   └───────────────────────┘                         └────────────┬─────────────┘
                                                                  │ TLS-terminated,
                                                                  │ then HTTP to:
                                                                  ▼
                                                  ┌──────────────────────────────┐
                                                  │ OpenRPort stack host         │
                                                  │ 10.0.0.5  (network_mode: host│
                                                  │   :38100 API, :38101 chisel, │
                                                  │   :38102 Pairing, :38103 UI, │
                                                  │   :38200-38400 tunnel pool)  │
                                                  └────────────┬─────────────────┘
                                                               │
   ┌───────────────────────┐                                   │
   │ Target host (agent)   │ 2. curl https://rport.example.com/pairing/<code>|sh
   │ 192.0.2.50            │ ─────────────────────────────────▶│  Pairing renders
   │ behind NAT, no inbound│                                   │  installer with
   │                       │ 3. installer downloads agent     │  CONNECT_URL +
   │                       │    binary (server or S3 mirror) ─▶  BINARIES_BASE_URL
   │                       │ 4. agent dials chisel WS to       │
   │                       │    OPENRPORT_SERVER_PUBLIC_URL ──▶│  rportd  :38101
   │                       │◀──── persistent control channel ──┤  (out-of-band:
   │                       │                                   │   no inbound
   │                       │                                   │   firewall on
   │                       │                                   │   agent side)
   └───────────────────────┘                                   └──────────────────┘
```

The agent only needs **outbound 443** (or whichever port
`OPENRPORT_SERVER_PUBLIC_URL` resolves to). Everything else rides on
that single chisel WebSocket.

### 2. Reverse-tunnel data path (operator → service behind agent)

```
                              tunnel pool port (raw TCP, bypasses proxy)
                              ┌──────────────────────────────────────────┐
                              │                                          ▼
   ┌───────────────────────┐  │  ┌──────────────────────────────┐  ┌──────────────┐
   │ Operator              │──┘  │ Stack host  10.0.0.5         │  │ rportd       │
   │ 198.51.100.10         │     │ tunnels.rport.example.com    │──│ 0.0.0.0:38250│
   │  rdp / ssh / browser /│────▶│   :38250  (allocated from    │  │ (allocated)  │
   │  curl  to             │     │   OPENRPORT_TUNNEL_USED_PORTS)  └──────┬───────┘
   │  tunnels.rport....    │     └──────────────────────────────┘         │
   │     :38250            │                                              │ multiplexed
   └───────────────────────┘                                              │ over the
                                                                          ▼ existing chisel WS
                                                       ┌──────────────────────────┐
                                                       │ Agent  192.0.2.50        │
                                                       │  rport client            │
                                                       │  forwards 38250 →        │
                                                       │  127.0.0.1:<svc>         │
                                                       └────────────┬─────────────┘
                                                                    ▼
                                                  ┌──────────────────────────────────┐
                                                  │ Local service on the agent host  │
                                                  │   :3389  RDP                     │
                                                  │   :22    SSH                     │
                                                  │   :80    intranet web            │
                                                  │   :5432  Postgres (TCP)          │
                                                  │   :161   SNMP (UDP)              │
                                                  └──────────────────────────────────┘
```

What the operator sees in the UI: `tunnels.rport.example.com:38250` (or
whatever `OPENRPORT_TUNNEL_HOST` resolves to, falling back to the API
host). The TCP/UDP connection lands on rportd's allocated pool port,
gets multiplexed onto the agent's existing chisel WebSocket, and the
agent forwards it to the chosen `127.0.0.1:<port>` on its loopback —
no inbound firewall change on the agent side.

### 3. Agent binary delivery (server-hosted vs. S3 mirror)

```
                         ┌──────────────────────────────────────────┐
                         │ Pairing service renders installer with    │
                         │   BINARIES_BASE_URL = OPENRPORT_BINARIES_PUBLIC_URL
                         └──────────────────────────────────────────┘
                                  │
              ┌───────────────────┴────────────────────┐
              ▼                                        ▼
    DEFAULT (server-hosted)                   OPTIONAL (S3 / CDN mirror)
    ┌─────────────────────────────┐           ┌─────────────────────────────┐
    │ OPENRPORT_BINARIES_PUBLIC_  │           │ OPENRPORT_BINARIES_PUBLIC_  │
    │   URL=https://rport...      │           │   URL=https://cdn.example...│
    │   /binaries                 │           │   /openrport/binaries       │
    │                             │           │                             │
    │ Pairing serves the files    │           │ Bucket holds the same       │
    │ bind-mounted from           │           │ layout (rport_<os>_<arch>   │
    │ Data/OpenRPort/Binaries/    │           │ + checksum). No traffic     │
    │ via [downloads] in          │           │ hits the stack for the      │
    │ config.toml.                │           │ binary download itself.     │
    └─────────────────────────────┘           └─────────────────────────────┘
              │                                        │
              └────────────────────┬───────────────────┘
                                   ▼
                       Agent installer fetches:
                         <BINARIES_BASE_URL>/rport_<os>_<arch>.tar.gz
                         <BINARIES_BASE_URL>/rport_<os>_<arch>.sha256
```

To switch to an S3/CDN mirror: upload the contents of
`Data/OpenRPort/Binaries/` to your bucket (preserving the filenames /
checksum sidecars) and point `OPENRPORT_BINARIES_PUBLIC_URL` at the
public base URL. Pairing-rendered installers will fetch from there
instead of the stack — useful when agents are far from the server or
when you want to keep the stack off the binary-download hot path.

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
