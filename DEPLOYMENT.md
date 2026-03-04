# Telemt — Personal Deployment Configuration

Custom configuration for deploying Telemt as a Telegram MTProto proxy with
maximum DPI evasion, optimized for restrictive network environments.

Deployed via [Dokploy](https://dokploy.com/) with Traefik TCP passthrough.

---

## Architecture

```
Client (Telegram)
  │
  │  TLS ClientHello, SNI = www.google.com
  ▼
Traefik (:443)
  │
  │  HostSNI("www.google.com") → TCP passthrough (no TLS termination)
  ▼
Telemt container (:443 internal)
  │
  │  FakeTLS unwrap → MTProto → Telegram DCs
  ▼
Telegram Servers
```

Traefik routes traffic based on the TLS SNI header:
- `www.google.com` → raw TCP passthrough to Telemt (proxy traffic)
- `deploy.aitb.ir` → TLS termination → Dokploy UI (management)
- Any other SNI → Traefik default handling (404)

---

## What Was Changed

### `config.toml` — Full DPI Evasion Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| `tls_domain` | `www.google.com` | SNI that DPI sees; unblocked, high-traffic, plausible on AWS |
| `mask` | `true` | Failed handshakes forwarded to real Google (active probe masking) |
| `tls_emulation` | `true` | Fetches real Google TLS cert chain; byte-perfect record sizes |
| `server_hello_delay` | `50–150ms` | Mimics real HTTPS server response timing |
| `tls_new_session_tickets` | `2` | Matches Google's TLS 1.3 behavior (zero tickets is anomalous) |
| `tls_full_cert_ttl_secs` | `0` | Every connection gets identical cert (no size variation) |
| `alpn_enforce` | `true` | Prevents ALPN mismatch detection |
| `fast_mode` | `true` | Coalesces handshake + payload into single TCP packet |
| `fast_mode_min_tls_record` | `1400` | Realistic TLS record sizing (matches HTTPS MTU) |
| `replay_check_len` | `65536` | Blocks DPI replay attack probing |
| `replay_window_secs` | `1800` | 30-minute replay detection window |
| `beobachten` | `true` | Tracks suspicious IPs (scanners, crawlers, probers) |
| `desync_all_full` | `true` | Full forensics for DPI tampering detection |
| `ntp_check` | `true` | Clock accuracy check (MTProto requires it) |
| Modes | `tls` only | Classic and Secure disabled (trivially detectable) |
| Mode | Direct | No Middle-End (simpler, lower overhead) |

### `docker-compose.yml` — Traefik Integration

- **No direct port 443 mapping** — Traefik handles all ingress
- **Docker labels** tell Traefik to create a TCP passthrough route automatically
- **`dokploy-network`** (external) — container joins Dokploy's shared network
- **Security hardening** — read-only filesystem, dropped capabilities, no-new-privileges
- **2MB tmpfs** at `/run/telemt` for TLS cert cache and beobachten logs

### `setup.sh` — Diagnostic Tool

Optional script for troubleshooting via SSH. Checks:
- Docker and network status
- Traefik configuration and Docker socket access
- Container labels and network membership
- Port conflicts and stale configurations

### `DEPLOYMENT.md` — This File

---

## Prerequisites

1. **Server** with Dokploy installed and Traefik running
2. **Cloudflare DNS** — A record for the proxy subdomain:
   - Type: `A`
   - Name: `api` (or your chosen subdomain)
   - Content: your server's public IP
   - Proxy status: **DNS only** (gray cloud, NOT orange)

> Cloudflare-proxied (orange cloud) will NOT work — it terminates TLS,
> which destroys the FakeTLS layer that Telemt uses.

---

## Deployment via Dokploy

### Step 1 — Remove old deployment

If you have an existing Telemt deployment in Dokploy that maps port 443
directly, stop and delete it first. Direct port mapping conflicts with
Traefik.

### Step 2 — Create new Compose service

1. In Dokploy UI, create a new **Docker Compose** service
2. Point it to your fork: `https://github.com/ali-rajabpour/telemt`
3. Set the branch to: `personal`
4. No ENV variables needed — everything is in `config.toml`

### Step 3 — Deploy

Click **Deploy**. Dokploy runs `docker compose up`. The container starts
with Traefik labels on `dokploy-network`. Traefik auto-discovers the
container via the Docker socket and creates the TCP passthrough route.

No manual Traefik configuration required.

### Step 4 — Get the tg:// link

In Dokploy, open the **Logs** tab for the Telemt service. The startup
output contains the proxy link:

```
tg://proxy?server=api.aitb.ir&port=443&secret=ee...
```

Share this link with your users.

---

## Deploying on a Different Server

The project is fully self-contained. On a new server with Dokploy:

1. Ensure Cloudflare DNS points your subdomain to the new server IP (gray cloud)
2. Edit `config.toml`:
   - Change `announce` in `[[server.listeners]]` to the new server's public IP
   - Change `public_host` in `[general.links]` to the new subdomain
3. Deploy through Dokploy UI as described above

---

## Managing User Secrets

Generate a new secret:

```bash
openssl rand -hex 16
```

Add it to `config.toml` under `[access.users]`:

```toml
[access.users]
main = "your_32_hex_secret_here"
```

Redeploy through Dokploy to apply.

Optional per-user controls (add to `config.toml`):

```toml
[access.user_max_tcp_conns]
main = 100

[access.user_max_unique_ips]
main = 3    # phone + desktop + tablet

[access.user_expirations]
main = "2026-12-31T23:59:59Z"

[access.user_data_quota]
main = 107374182400   # 100 GB
```

---

## Diagnostics

SSH into the server and run:

```bash
cd /path/to/telemt
./setup.sh
```

This checks Docker, network, Traefik, container labels, port conflicts,
and stale configurations. It makes no changes — read-only diagnostics.

---

## Syncing with Upstream

This branch is based on the upstream `telemt/telemt` repo. To pull in
future updates:

```bash
git fetch upstream
git merge upstream/main
```

Resolve any conflicts in `config.toml` or `docker-compose.yml` (your
customizations), then push to the `personal` branch.

---

## Security Notes

- The user secret in `config.toml` is committed to the repo. If your
  fork is **private**, this is acceptable. If **public**, consider using
  Dokploy ENV variables or a `.gitignore`d config overlay.
- Classic and Secure MTProto modes are disabled — only FakeTLS (ee-secrets)
  is accepted. This is intentional for maximum stealth.
- The `beobachten` tracker logs suspicious IPs to `cache/beobachten.txt`
  inside the container's tmpfs. This data is lost on container restart.
  For persistent tracking, mount an external volume.
