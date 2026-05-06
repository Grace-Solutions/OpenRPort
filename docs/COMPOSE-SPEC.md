# Docker Compose Stack Specification

## File Header
```yaml
#=============================================================================
# {STACK_NAME} - {Description}
# {URL}
#=============================================================================
#
# CREDENTIALS:
#   {credential format}
#
# PRODUCTION SETUP:
#   1. {step}
#   2. {step}
#
# ENDPOINTS:
#   - {endpoint}: {url}
#
#=============================================================================

name: '${STACK_NAME:-stk-{name}-00001}'
```

## Networks
```yaml
networks:
  EXTERNAL:
    name: {STACKNAME}-EXTERNAL
    driver: bridge
    internal: false
    attachable: true
  INTERNAL:
    name: {STACKNAME}-INTERNAL
    driver: bridge
    internal: true
    attachable: true
```

## Services

### Container Naming
- Format: `{STACKNAME}-{TIER}-00001`
- Tiers: `DB`, `CACHE`, `APP`, `WORKER`, `PROXY`
- Example: `NETBOX-DB-00001`, `CLOUDREVE-APP-00001`

### No Hostnames
- Do NOT use `hostname:` - use compose service names for internal networking
- Reference other services by service name: `DB`, `Cache`, `App`

### Standard Service Block
```yaml
  {ServiceName}:
    image: '${IMAGE:-default/image}:${VERSION:-tag}'
    container_name: {STACKNAME}-{TIER}-00001
    restart: unless-stopped
    stop_signal: SIGTERM
    stop_grace_period: 30s
    user: "${PUID:-1000}:${PGID:-1000}"
    logging:
      driver: 'local'
    networks:
      INTERNAL:
    environment:
      VAR_NAME: '${VAR_NAME:-DefaultValue}'
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - "${STACK_BINDMOUNTROOT:-/mnt/docker/stacks}/${STACK_NAME:-stk-name-00001}/{Tier}/Data:/container/path:rw"
    healthcheck:
      test: ["CMD", "command", "args"]
      start_period: 30s
      interval: 10s
      retries: 5
      timeout: 5s
    labels:
      com.centurylinklabs.watchtower.enable: '${ENABLEAUTOMATICUPDATES:-false}'
```

## Bind Mounts
- Format: `"${STACK_BINDMOUNTROOT:-/mnt/data/docker/stacks}/${STACK_NAME:-stk-name-00001}/{Tier}/Data:/container/path:rw"`
- Tiers: `App`, `DB`, `Cache`
- Always use `:rw` or `:ro` suffix

## Secrets & Defaults
- Compose defaults MUST differ from .env values
- Both must be actual secure random strings (not placeholder text)
- Generate with: `openssl rand -base64 24` (passwords) or `openssl rand -base64 50` (keys)
- Compose: `${PASSWORD:-xK9mZ7vQ3wL8nP2jR5tY0uA4}` (random default)
- .env: `PASSWORD=bH3nF6kM9pL2sW5xY8cD1eG4` (different random value)

## Image Variables
```yaml
image: '${IMAGE_NAME:-default/image}:${IMAGE_VERSION:-tag}'
```
Examples:
- `'${POSTGRES_IMAGE:-postgres}:${POSTGRES_VERSION:-17-alpine}'`
- `'${VALKEY_IMAGE:-valkey/valkey}:${VALKEY_VERSION:-9.0-alpine}'`

## Cache (Valkey)
Always use Valkey, never Redis:
```yaml
  Cache:
    image: '${VALKEY_IMAGE:-valkey/valkey}:${VALKEY_VERSION:-9.0-alpine}'
    container_name: {STACKNAME}-CACHE-00001
    command: ["valkey-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD:-DefaultCachePass123}"]
```

## Network References
- Internal services reference each other by **service name**: `DB`, `Cache`, `App`
- NOT by container name: ~~`NETBOX-DB-00001`~~

