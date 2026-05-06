# Agent Handoff Document — OpenRPort Unified Deployment

**Status as of push `bb237676`**
**Date:** 2026-05-06
**Repo:** https://github.com/Grace-Solutions/OpenRPort (branch: `main`)
**Development context moving to:** Linux (Docker available)

---

## What This Repo Is

A **unified, single-`docker compose up` deployment** of three upstream projects:

| Service | Upstream repo | Local path |
|---------|--------------|-----------|
| `openrport-server` | github.com/openrport/openrport (master) | `src/Server/` |
| `openrport-pairing` | github.com/openrport/rport-pairing (main) | `src/Pairing/` |
| `openrport-ui` | github.com/openrport/openrport-ui (main) | `src/Ui/` |

Sources are integrated as **git subtrees** (not submodules). No reverse proxy container. Everything is environment-variable driven. Spec is at `docs/DesignSpec.md`.

---

## Repo Layout (what exists now)

```
OpenRPort/
├── compose.yaml              ← 3-service stack, fully env-driven
├── .env.example              ← All variables documented, copy to .env
├── Makefile                  ← lint / build / up / down / test targets
├── .gitignore
├── docs/
│   ├── DesignSpec.md         ← Original spec
│   └── AgentHandoff.md       ← THIS FILE
├── scripts/
│   ├── AddSubtrees.sh        ← One-time: adds all 3 git subtrees
│   ├── UpdateSubtrees.sh     ← Pulls latest from all 3 upstreams
│   ├── ValidateEnv.sh        ← Validates .env rules (sourced by GenerateConfig)
│   ├── GenerateConfig.sh     ← Generates Config/{Server,Pairing,Ui}/ files
│   └── TestStack.sh          ← Integration test (run after make up)
├── Container/
│   ├── Server/
│   │   ├── Dockerfile        ← Multi-stage Go build → Debian slim runtime
│   │   └── entrypoint.sh     ← Resolves pairing URL, patches config, runs rportd -c
│   ├── Pairing/
│   │   ├── Dockerfile        ← Multi-stage Go build → Debian slim runtime
│   │   └── entrypoint.sh     ← Resolves public URL, patches TOML config, runs rport-pairing -c
│   └── Ui/
│       ├── Dockerfile        ← Node 20 build (yarn build → nuxt build) → Node slim runtime
│       └── entrypoint.sh     ← Sets NUXT_PUBLIC_API_URL, runs node .output/server/index.mjs
├── Config/
│   ├── Server/.gitkeep       ← rportd.conf written here by GenerateConfig.sh
│   ├── Pairing/.gitkeep      ← config.toml written here by GenerateConfig.sh
│   └── Ui/.gitkeep           ← runtime.env written here by GenerateConfig.sh
└── src/
    ├── Server/               ← git subtree: openrport/openrport@ea4fd08 (master)
    ├── Pairing/              ← git subtree: openrport/rport-pairing@3082bb54 (main)
    └── Ui/                   ← git subtree: openrport/openrport-ui@885d9af0 (main)
```

---

## What Has Been Verified (Windows, no Docker)

- ✅ All scaffold files written and committed
- ✅ All 3 git subtrees added correctly (Server: 27 items, Pairing: full Go project, Ui: full Nuxt project)
- ✅ Upstream source structure confirmed:
  - `rportd` built from `./cmd/rportd` with `CGO_ENABLED=0`
  - `rport-pairing` built from `./cmd/rport-pairing.go` with `CGO_ENABLED=0`
  - UI is Nuxt 3 SPA (`ssr: false`), uses `yarn build` → `nuxt build`, serves via `node .output/server/index.mjs`
  - Both Go services use `-c <config-file>` flag (NOT `--config`)
  - rport-pairing config is **TOML** format with `[server] url = "..."` (NOT yaml)
  - rportd config is TOML: `[server]` for client port (8081), `[api]` for API port (8080)
- ✅ Pushed to `origin/main`

## What Has NOT Been Tested Yet (needs Linux + Docker)

- ❌ `docker compose build` — none of the 3 containers have been built
- ❌ `docker compose up` — services have not been started
- ❌ `scripts/TestStack.sh` — integration tests not run
- ❌ `scripts/GenerateConfig.sh` — not run on Linux (scripts are bash, Windows has no bash)
- ❌ `scripts/ValidateEnv.sh` — same

---

## Phase Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1 – Scaffold | ✅ COMPLETE | Committed and pushed |
| Phase 2 – Container Builds | 🔲 NOT STARTED | First task on Linux |
| Phase 3 – Config Generation | 🔲 NOT STARTED | Run GenerateConfig.sh, fix bugs |
| Phase 4 – Header Discovery | 🔲 NOT STARTED | Test with curl -H headers |
| Phase 5 – Subpath Support | 🔲 NOT STARTED | Verify /pairing and /ui paths |
| Phase 6 – Pairing Script Correctness | 🔲 NOT STARTED | Verify installer scripts |
| Phase 7 – UI Integration | 🔲 NOT STARTED | Verify NUXT_API_URL wiring |

---

## First Steps on Linux

```bash
# 1. Clone and enter repo
git clone https://github.com/Grace-Solutions/OpenRPort.git
cd OpenRPort

# 2. Copy and configure env
cp .env.example .env
# Edit .env – minimum: set RPORTD_API_PASSWORD to something non-default

# 3. Generate runtime configs
make generate-config
# This runs scripts/GenerateConfig.sh which writes:
#   Config/Server/rportd.conf
#   Config/Pairing/config.toml
#   Config/Ui/runtime.env

# 4. Try to build all containers (Phase 2)
make build
# Or: docker compose build

# 5. If build passes, start services
make up
# Or: docker compose up -d

# 6. Run integration tests (Phase 3+)
make test
# Or: bash scripts/TestStack.sh
```

---

## Known Issues / Things to Watch

### 1. rportd requires `key_seed` and `jwt_secret`
The example config has placeholders. `rportd` may fail to start without these.
In `Container/Server/entrypoint.sh`, add env var support:
```sh
KEY_SEED="${RPORTD_KEY_SEED:-$(openssl rand -hex 18)}"
JWT_SECRET="${RPORTD_JWT_SECRET:-$(openssl rand -hex 9)}"
```
Then substitute them into the generated config.

### 2. rportd `[logging]` section requires log dir
The example config writes logs to `/var/log/rport/rportd.log`. This directory may not exist in the container. Either:
- Create it in the Dockerfile, OR
- Override with `log_file = ""` (disables logging to file, uses stdout instead — better for containers)
The entrypoint.sh should set `log_file = ""` unless overridden.

### 3. rportd `[server] auth` is required
Without client auth, the server won't accept rport clients. The entrypoint already injects `auth = "${RPORTD_API_USER}:${RPORTD_API_PASSWORD}"` but note:
- `[server] auth` = client auth (for rport tunnel clients)
- `[api] auth` = API auth (for the UI/admin)
Both need to be set. Currently only API auth is in the fallback config. The Server entrypoint needs to add a `[server] auth` line.

### 4. UI is SPA (ssr: false) — base URL is baked at build time
`NUXT_APP_BASE_URL` is a **build-time** ARG in the Dockerfile. If you need `/ui` as base path, the image must be built with that value (which is the default). Changing the base path requires a rebuild.
`NUXT_PUBLIC_API_URL` **can** be overridden at runtime via the Nitro server.

### 5. rport-pairing health endpoint
The healthcheck in `compose.yaml` hits `GET /update` (returns an update script). This works but returns a large response. A better approach: check `curl -so /dev/null -w "%{http_code}" http://localhost:9978/update` expecting 200.

### 6. Server Dockerfile Go version
`src/Server/go.mod` requires `go 1.19` but Dockerfile uses `golang:1.21-bookworm`. This is fine (backward compatible) but verify the build doesn't hit any incompatibilities.

---

## Key Config Facts (discovered from source)

### rportd flags
```
rportd -c /path/to/rportd.conf     # load config file
rportd user ...                     # user management subcommand
```

### rport-pairing flags
```
rport-pairing -c /path/to/config   # load config file (TOML)
rport-pairing -v                    # print version
```

### rport-pairing TOML config format
```toml
[server]
  address = "0.0.0.0:9978"
  url = "https://pairing.example.com"   # ← this is the PUBLIC URL embedded in install scripts

[static-deposit]
  code = "0000000"           # test pairing code
  connect_url = "http://..."
  fingerprint = "aa:bb:cc"
  client_id = "testclient"
  password = "testpass"
```

### rportd TOML config (minimal working)
```toml
[server]
  address = "0.0.0.0:8081"          # where rport clients connect
  data_dir = "/var/lib/rport"
  auth = "clientid:clientpass"       # rport client auth
  key_seed = "<openssl rand -hex 18>"
  pairing_url = "http://openrport-pairing:9978"

[api]
  address = "0.0.0.0:8080"          # API port (UI connects here)
  auth = "admin:changeme"
  jwt_secret = "<openssl rand -hex 9>"

[logging]
  log_file = ""                      # empty = stdout (container-friendly)
  log_level = "info"
```

### Nuxt 3 UI env vars
```
NUXT_API_URL          → build-time default, maps to runtimeConfig.public.apiUrl
NUXT_PUBLIC_API_URL   → runtime override via Nitro, overrides runtimeConfig.public.apiUrl
NUXT_APP_BASE_URL     → build-time base path for assets/router (default: /ui)
```

---

## Deployment Philosophy (from DesignSpec.md)

- ❌ No reverse proxy container
- ❌ No TLS enforcement
- ❌ No hardcoded URLs
- ✅ Everything configurable via `.env`
- ✅ Header-based URL auto-discovery (`X-Forwarded-*` headers)
- ✅ Supports 4 deployment modes: `dns`, `subpath`, `internal`, `local`

---

## Recommended Incremental Commit Strategy (spec requirement)

For each phase:
1. Implement the smallest working change
2. `docker compose build` → fix errors → repeat
3. `docker compose up -d`
4. `bash scripts/TestStack.sh` → fix failures → repeat
5. `git add -A && git commit -m "feat: Phase N - <description>"`

Never batch multiple phases into one commit.

---

## Subtree Update Commands (for future upstream pulls)

```bash
bash scripts/UpdateSubtrees.sh
# or manually:
git subtree pull --prefix src/Server  https://github.com/openrport/openrport master --squash
git subtree pull --prefix src/Pairing https://github.com/openrport/rport-pairing main --squash
git subtree pull --prefix src/Ui      https://github.com/openrport/openrport-ui main --squash
```

---

## Commit History Summary

```
bb237676  fix: correct Dockerfile build commands and runtime entrypoints
f2513872  Merge: src/Ui subtree (openrport-ui@885d9af0)
d3e9c81e  Squashed src/Ui content
e8151580  Merge: src/Pairing subtree (rport-pairing@3082bb54)
f7e9a34b  Squashed src/Pairing content
c4d28aa8  Merge: src/Server subtree (openrport@ea4fd084)
1df4b6b4  Squashed src/Server content
f42bd270  feat: Phase 1 scaffold
13b4b466  Initial commit
```
