# Telemt - MTProxy on Rust + Tokio

[![Latest Release](https://img.shields.io/github/v/release/telemt/telemt?color=neon)](https://github.com/telemt/telemt/releases/latest) [![Stars](https://img.shields.io/github/stars/telemt/telemt?style=social)](https://github.com/telemt/telemt/stargazers) [![Forks](https://img.shields.io/github/forks/telemt/telemt?style=social)](https://github.com/telemt/telemt/network/members)

[🇷🇺 README на русском](https://github.com/telemt/telemt/blob/main/README.ru.md)

> [!NOTE]
>
> From August 22nd, 2026: we're drafting MTProxy WEB Implementation in Telemt!
> 
> It uses WebView on your device to create a datachannel!

<p align="center">
  <a href="https://t.me/telemtrs">
    <img src="https://github.com/user-attachments/assets/30b7e7b9-974a-4e3d-aab6-b58a85de4507" width="240"/>
  </a>
</p>

**Telemt** is a fast, secure, and feature-rich server written in Rust: it fully implements the official Telegram proxy algo and adds many production-ready improvements

### One-command Install and Update
```bash
curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh
```
- [Quick Start Guide](docs/Quick_start/QUICK_START_GUIDE.en.md)
- [Инструкция по быстрому запуску](docs/Quick_start/QUICK_START_GUIDE.ru.md)

### Deploying on Dokploy (shares port 443 with your websites)
`docker-compose-dokploy.yml` runs telemt behind Dokploy's Traefik on port 443. No extra
port is opened. Traefik reads the TLS SNI of each connection: if it equals your fake
domain (`TELEMT_CENSORSHIP__TLS_DOMAIN`), the connection is passed through to telemt
untouched; every other SNI keeps going to your websites.

1. In Dokploy, create a **Compose** service from this repo, compose path
   `./docker-compose-dokploy.yml`.
2. In its **Environment** tab set (see [.env.example](.env.example), section 6):
   ```env
   TELEMT_GENERAL__LINKS__PUBLIC_HOST=proxy.example.com   # your domain or server IP
   TELEMT_GENERAL__LINKS__PUBLIC_PORT=443
   TELEMT_CENSORSHIP__TLS_DOMAIN=petrovich.ru             # fake domain, never one you host here
   TELEMT_ACCESS__USERS__ALICE=<openssl rand -hex 16>
   ```
   If `PUBLIC_HOST` is a domain on Cloudflare, its DNS record must be **DNS only** (grey
   cloud). Cloudflare's proxy only carries HTTP and would break the connection.
   Any `config.toml` key can be set this way as `TELEMT_<SECTION>__<KEY>` (nested sections
   joined with `__`); env values override the file. `config.toml` ships with no users, so
   at least one `TELEMT_ACCESS__USERS__<NAME>` is required.
3. Deploy. Nothing needs to be configured in Traefik; the compose labels add the route.
4. Get the share link from the container log:
   ```bash
   docker logs $(docker ps -qf name=telemt) 2>&1 | grep -o 'tg://proxy[^ ]*' | tail -1
   ```
   It looks like `tg://proxy?server=proxy.example.com&port=443&secret=ee…`. Open it on a
   device with Telegram, or send it to your users.

Changing `TLS_DOMAIN`, a user secret, or `PUBLIC_HOST`/`PUBLIC_PORT` changes the link, so
send the new one to your users. Telemt sees real client IPs only if Traefik receives them,
which requires Traefik's port 443 to be published in `host` mode. Swarm's default
`ingress` mode hides them.

## Features
Our implementation of **TLS-fronting** is one of the most deeply debugged, focused, advanced and *almost* **"behaviorally consistent to real"**:  we are confident we have it right - [see evidence on our validation and traces](docs/FAQ.en.md#recognizability-for-dpi-and-crawler)

Our ***Middle-End Pool*** is fastest by design in standard scenarios, compared to other implementations of connecting to the Middle-End Proxy: non dramatically, but usual

- Full support for all official MTProto proxy modes:
  - Classic;
  - Secure - with `dd` prefix;
  - Fake TLS - with `ee` prefix + SNI fronting;
- Replay attack protection;
- Optional traffic masking: forward unrecognized connections to a real web server, e.g. GitHub 🤪;
- Configurable keepalives + timeouts + IPv6 and "Fast Mode";
- Graceful shutdown on Ctrl+C;
- Extensive logging via `trace` and `debug` with `RUST_LOG` method.

## FAQ
- [FAQ RU](docs/FAQ.ru.md)
- [FAQ EN](docs/FAQ.en.md)

# Learn more about Telemt
- [Our Architecture](docs/Architecture)
- [All Config Options](docs/Config_params)
- [How to build your own Telemt?](#build)
- [Running on BSD](docs/Quick_start/OPENBSD_QUICK_START_GUIDE.en.md)
- [Why Rust?](#why-rust)

## Build
```bash
# Cloning repo
git clone https://github.com/telemt/telemt 
# Changing Directory to telemt
cd telemt
# Starting Release Build
cargo build --release

# Current release profile uses lto = "fat" for maximum optimization (see Cargo.toml).
# On low-RAM systems (~1 GB) you can override it to "thin".

# Move to /bin
mv ./target/release/telemt /bin
# Make executable
chmod +x /bin/telemt
# Lets go!
telemt config.toml
```

## Why Rust?
- Long-running reliability and idempotent behavior
- Rust's deterministic resource management - RAII 
- No garbage collector
- Memory safety and reduced attack surface
- Tokio's asynchronous architecture

## Support Telemt

Telemt is free, open-source, and built in personal time.
If it helps you — consider supporting continued development.

Any cryptocurrency (BTC, ETH, USDT, 350+ coins):

<p align="center">
  <a href="https://nowpayments.io/donation?api_key=2bf1afd2-abc2-49f9-a012-f1e715b37223" target="_blank" rel="noreferrer noopener">
    <img src="https://nowpayments.io/images/embeds/donation-button-white.svg" alt="Cryptocurrency & Bitcoin donation button by NOWPayments" height="80">
  </a>
</p>

Monero (XMR) directly:

```
8Bk4tZEYPQWSypeD2hrUXG2rKbAKF16GqEN942ZdAP5cFdSqW6h4DwkP5cJMAdszzuPeHeHZPTyjWWFwzeFdjuci3ktfMoB
```

All donations go toward infrastructure, development and research


![telemt_scheme](docs/assets/telemt.png)
