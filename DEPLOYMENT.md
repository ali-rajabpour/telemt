# Telemt — Personal Deployment Configuration

Custom configuration for deploying Telemt as a Telegram MTProto proxy with
maximum DPI evasion, optimized for restrictive network environments.

Deployed via [Dokploy](https://dokploy.com/) with Traefik TCP passthrough.

---

## Architecture

```
Client (Telegram)
  |
  |  TLS ClientHello, SNI = $TELEMT_TLS_DOMAIN
  v
Traefik (:443)
  |
  |  HostSNI match -> TCP passthrough (no TLS termination)
  v
Telemt container (:443 internal)
  |
  |  FakeTLS unwrap -> MTProto -> Telegram DCs
  v
Telegram Servers
```

Traefik routes traffic based on the TLS SNI header:
- `$TELEMT_TLS_DOMAIN` SNI -> raw TCP passthrough to Telemt (proxy traffic)
- `deploy.aitb.ir` SNI -> TLS termination -> Dokploy UI (management)
- Any other SNI -> Traefik default handling (404)

---

## Environment Variables

Configuration is done entirely through environment variables, set in
Dokploy's UI or in a `.env` file for local development.

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `TELEMT_SECRET` | 32-hex proxy secret. Generate: `openssl rand -hex 16` | `545d50e4498f...` |
| `TELEMT_SERVER_IP` | Server's public IP (for announce/routing) | `47.128.145.75` |
| `TELEMT_PUBLIC_HOST` | Domain or IP for tg:// links (DNS-only in Cloudflare) | `api.aitb.ir` |

### Optional (have defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `TELEMT_TLS_DOMAIN` | `www.google.com` | SNI domain for FakeTLS; must be unblocked in target country |
| `TELEMT_USER_NAME` | `main` | Internal label for the secret |
| `TELEMT_PORT` | `443` | Listen port inside the container |
| `TELEMT_PUBLIC_PORT` | `443` | Port in the tg:// link |
| `TELEMT_LOG_LEVEL` | `normal` | Verbosity: debug, verbose, normal, silent |

See `.env.example` for full documentation.

---

## DPI Evasion Settings (Built-in)

These are hardcoded in the generated config for maximum stealth.
They do not need ENV vars because they should not change:

| Setting | Value | Purpose |
|---------|-------|---------|
| `mask` | `true` | Failed handshakes forwarded to real website (active probe masking) |
| `tls_emulation` | `true` | Byte-perfect TLS certificate emulation from real server |
| `server_hello_delay` | `50-150ms` | Mimics real HTTPS server response timing |
| `tls_new_session_tickets` | `2` | Matches typical TLS 1.3 behavior |
| `tls_full_cert_ttl_secs` | `0` | Every connection gets identical cert (no size variation) |
| `alpn_enforce` | `true` | Prevents ALPN mismatch detection |
| `fast_mode` | `true` | Coalesces handshake + payload into single TCP packet |
| `fast_mode_min_tls_record` | `1400` | Realistic TLS record sizing (matches HTTPS MTU) |
| `replay_check_len` | `65536` | Blocks DPI replay attack probing |
| `beobachten` | `true` | Tracks suspicious IPs (scanners, crawlers, probers) |
| `desync_all_full` | `true` | Full forensics for DPI tampering detection |
| Modes | `tls` only | Classic and Secure disabled (trivially detectable by DPI) |

---

## Prerequisites

1. **Server** with Dokploy installed and Traefik running
2. **Cloudflare DNS** -- A record for the proxy subdomain:
   - Type: `A`
   - Name: your chosen subdomain (e.g., `api`)
   - Content: your server's public IP
   - Proxy status: **DNS only** (gray cloud, NOT orange)

> Cloudflare-proxied (orange cloud) will NOT work -- it terminates TLS,
> which destroys the FakeTLS layer that Telemt uses.

---

## Deployment via Dokploy

### Step 1 -- Remove old deployment

If you have an existing Telemt deployment in Dokploy that maps port 443
directly, stop and delete it first. Direct port mapping conflicts with
Traefik.

### Step 2 -- Create new Compose service

1. In Dokploy UI, create a new **Docker Compose** service
2. Point it to: `https://github.com/ali-rajabpour/telemt`
3. Set the branch to: `personal`

### Step 3 -- Set environment variables

In the Dokploy service settings, add these ENV variables:

```
TELEMT_SECRET=<your 32-hex secret>
TELEMT_SERVER_IP=<your server public IP>
TELEMT_PUBLIC_HOST=<your proxy subdomain>
```

Optional (only if you want to override defaults):

```
TELEMT_TLS_DOMAIN=www.google.com
TELEMT_USER_NAME=main
TELEMT_PORT=443
TELEMT_PUBLIC_PORT=443
TELEMT_LOG_LEVEL=normal
```

### Step 4 -- Deploy

Click **Deploy**. What happens automatically:

1. Docker builds the image from the Dockerfile
2. The entrypoint script generates `config.toml` from your ENV variables
3. The container starts on `dokploy-network` with Traefik labels
4. Traefik discovers the container and creates the TCP passthrough route
5. Proxy is live

### Step 5 -- Get the tg:// link

In Dokploy, open the **Logs** tab. The startup output shows:

```
[entrypoint] Config generated:
  secret:      main = 545d50e4...
  server_ip:   47.128.145.75
  public_host: api.aitb.ir:443
  tls_domain:  www.google.com
[entrypoint] Starting telemt...
```

The `tg://proxy?server=...&secret=ee...` link appears shortly after.

---

## Deploying on a Different Server

No code changes needed. Just set different ENV variables in Dokploy:

1. Create Cloudflare DNS A record for the new subdomain (gray cloud)
2. Create a new Compose service in Dokploy pointing to the same repo/branch
3. Set the three required ENV variables with the new server's values
4. Deploy

---

## Advanced: Static config.toml

For multi-user setups or settings not exposed as ENV vars, you can use a
hand-crafted `config.toml` instead. Uncomment the volume mount in
`docker-compose.yml`:

```yaml
volumes:
  - ./config.toml:/run/telemt/config.toml:ro
```

When the entrypoint detects a mounted config.toml, it skips generation
and uses it as-is. ENV variables are ignored in this mode.

---

## Diagnostics

SSH into the server and run:

```bash
cd /path/to/telemt
./setup.sh
```

Checks Docker, network, Traefik, container labels, port conflicts,
and stale configurations. Read-only -- makes no changes.

---

## Syncing with Upstream

This branch is based on the upstream `telemt/telemt` repo. To pull in
future updates:

```bash
git fetch upstream
git merge upstream/main
```

Resolve any conflicts in `docker-compose.yml`, `Dockerfile`, or
`entrypoint.sh` (your customizations), then push to `personal`.

---

## Security Notes

- Secrets are in ENV variables, never committed to git. The `.env` file
  is in `.gitignore`.
- Classic and Secure MTProto modes are disabled -- only FakeTLS
  (ee-secrets) is accepted. This is intentional for maximum stealth.
- The `beobachten` tracker logs suspicious IPs inside the container's
  tmpfs. Data is lost on container restart. For persistent tracking,
  mount an external volume.
