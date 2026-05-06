# Environment File Specification

## File Header
```bash
#=============================================================================
# {STACK_NAME} - {Description}
#=============================================================================
#
# CREDENTIALS:
#   {credential format}
#
# ACCESS URL: {url}
#
# PRODUCTION SETUP:
#   1. {step}
#   2. {step}
#
#=============================================================================
```

## Required Variables

### Stack Identity
```bash
# Stack Identity
STACK_NAME=stk-{name}-00001
STACK_BINDMOUNTROOT=/mnt/data/docker/stacks
```

### Container User/Group
```bash
# Container User/Group
PUID=0
PGID=0
```
- Default in compose: `${PUID:-1000}:${PGID:-1000}`
- Set to `0` for root, or match host user UID/GID

## Images
```bash
# Images
{APP}_IMAGE={default/image}
{APP}_VERSION={tag}
POSTGRES_IMAGE=postgres
POSTGRES_VERSION=17@sha256:14a603c5f403a0e00e6523650e1fded81d765bfbd5a6afcef29924cec8b139ac
VALKEY_IMAGE=valkey/valkey
VALKEY_VERSION=9.0-alpine
BUSYBOX_IMAGE=busybox
BUSYBOX_VERSION=latest
```

## Ports
```bash
# Ports
{APP}_PORT={port}
```

## Database
```bash
# Database
POSTGRES_USER={appname}
POSTGRES_PASSWORD={SecurePassword}
POSTGRES_DB={appname}
```

## Cache
```bash
# Cache (Valkey/Redis)
REDIS_PASSWORD={SecurePassword}
```

## Secrets
```bash
# Secrets (regenerate for production)
SECRET_KEY={50+ character random string}
```
Generate with: `openssl rand -base64 50`

## Automatic Updates
```bash
# Automatic Updates (Watchtower)
{APP}_ENABLEAUTOMATICUPDATES=false
POSTGRES_ENABLEAUTOMATICUPDATES=false
VALKEY_ENABLEAUTOMATICUPDATES=false
```

## Secret Value Rules

### .env vs Compose Defaults
| Location | Purpose | Example |
|----------|---------|---------|
| .env | Actual random secret | `bH3nF6kM9pL2sW5xY8cD1eG4` |
| Compose default | Different random secret | `xK9mZ7vQ3wL8nP2jR5tY0uA4` |

### Generation
```bash
# Passwords (24 chars)
openssl rand -base64 24

# Secret keys (50+ chars)
openssl rand -base64 50

# Hash salts (hex)
openssl rand -hex 16
```

### Why Different?
- Both are real secrets, but different values
- If .env is missing, stack still runs but with different credentials
- Logs/debugging can identify which secret source is active

## Example Complete .env
```bash
#=============================================================================
# NETBOX - Network Documentation & IPAM
#=============================================================================
#
# CREDENTIALS:
#   Username: admin
#   Password: Adm1n5ecur3P@ss2024
#
# ACCESS URL: http://localhost:8000/
#
#=============================================================================

# Stack Identity
STACK_NAME=stk-netbox-00001
STACK_BINDMOUNTROOT=/mnt/data/docker/stacks

# Container User/Group
PUID=0
PGID=0

# Images
NETBOX_IMAGE=netboxcommunity/netbox
NETBOX_VERSION=v4.2
POSTGRES_IMAGE=postgres
POSTGRES_VERSION=17@sha256:14a603c5f403a0e00e6523650e1fded81d765bfbd5a6afcef29924cec8b139ac
VALKEY_IMAGE=valkey/valkey
VALKEY_VERSION=9.0-alpine
BUSYBOX_IMAGE=busybox
BUSYBOX_VERSION=latest

# Ports
NETBOX_PORT=8000

# Database
POSTGRES_USER=netbox
POSTGRES_PASSWORD=N3tb0x5ecur3P@ssw0rd2024
POSTGRES_DB=netbox

# Cache
REDIS_PASSWORD=V@lk3yN3tb0xP@ss2024

# Secrets
SECRET_KEY=Kx9mZ7vQ3wL8nP2jR5tY0uA4cF6hB1dE9sW3xN7mJ2kP5vT8yG0qC4rU6iO1aM3z

# Superuser
SUPERUSER_NAME=admin
SUPERUSER_EMAIL=admin@example.com
SUPERUSER_PASSWORD=Adm1n5ecur3P@ss2024
SKIP_SUPERUSER=false

# Automatic Updates
NETBOX_ENABLEAUTOMATICUPDATES=true
POSTGRES_ENABLEAUTOMATICUPDATES=false
VALKEY_ENABLEAUTOMATICUPDATES=false
```

