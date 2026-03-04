#!/usr/bin/env bash
# ==============================================================================
# Telemt Diagnostic Script
#
# Validates that the Dokploy + Traefik + telemt setup is correct.
# No manual Traefik configuration needed — Docker labels in docker-compose.yml
# handle all routing automatically when deployed through Dokploy.
#
# Usage:
#   ./setup.sh           # Run all diagnostics
#   ./setup.sh --check   # Same as above (alias)
# ==============================================================================

set -euo pipefail

# --- Configuration ---
DOKPLOY_NETWORK="dokploy-network"
CONTAINER_NAME="telemt"
TLS_DOMAIN="www.google.com"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC}  $1"; }

ERRORS=0
WARNINGS=0

echo ""
echo "================================================"
echo "  Telemt — Deployment Diagnostics"
echo "================================================"
echo ""

# --- Check 1: Docker running ---
echo "--- Infrastructure ---"
if docker info &>/dev/null; then
    ok "Docker is running"
else
    fail "Docker is not running or not accessible"
    ERRORS=$((ERRORS + 1))
fi

# --- Check 2: dokploy-network ---
if docker network inspect "$DOKPLOY_NETWORK" &>/dev/null; then
    ATTACHABLE=$(docker network inspect "$DOKPLOY_NETWORK" --format '{{.Attachable}}' 2>/dev/null)
    if [[ "$ATTACHABLE" == "true" ]]; then
        ok "Network '$DOKPLOY_NETWORK' exists and is attachable"
    else
        fail "Network '$DOKPLOY_NETWORK' is NOT attachable — containers cannot join it"
        info "Fix: docker network update --attachable $DOKPLOY_NETWORK"
        ERRORS=$((ERRORS + 1))
    fi
else
    fail "Network '$DOKPLOY_NETWORK' does not exist — is Dokploy installed?"
    ERRORS=$((ERRORS + 1))
fi

# --- Check 3: Traefik ---
if docker ps --format '{{.Names}}' | grep -q 'dokploy-traefik'; then
    TRAEFIK_IMAGE=$(docker inspect dokploy-traefik --format '{{.Config.Image}}' 2>/dev/null)
    ok "Traefik is running ($TRAEFIK_IMAGE)"

    # Verify Traefik has Docker socket
    HAS_SOCK=$(docker inspect dokploy-traefik --format '{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}yes{{end}}{{end}}' 2>/dev/null)
    if [[ "$HAS_SOCK" == "yes" ]]; then
        ok "Traefik has Docker socket access (can discover labels)"
    else
        fail "Traefik does NOT have Docker socket — labels won't work"
        ERRORS=$((ERRORS + 1))
    fi

    # Verify Traefik is on dokploy-network
    TRAEFIK_NETS=$(docker inspect dokploy-traefik --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
    if echo "$TRAEFIK_NETS" | grep -q "$DOKPLOY_NETWORK"; then
        ok "Traefik is on '$DOKPLOY_NETWORK'"
    else
        fail "Traefik is NOT on '$DOKPLOY_NETWORK' — cannot reach telemt container"
        ERRORS=$((ERRORS + 1))
    fi
else
    fail "Traefik container 'dokploy-traefik' is not running"
    ERRORS=$((ERRORS + 1))
fi

# --- Check 4: Port 443 conflict ---
PORT_443_CONTAINER=$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep '0.0.0.0:443->' | grep -v 'dokploy-traefik' | awk '{print $1}' || true)
if [[ -n "$PORT_443_CONTAINER" ]]; then
    fail "Port 443 is directly bound by container '$PORT_443_CONTAINER' (conflicts with Traefik)"
    info "Stop it: docker stop $PORT_443_CONTAINER"
    info "Or remove the old deployment in Dokploy UI"
    ERRORS=$((ERRORS + 1))
else
    ok "No port 443 conflict (only Traefik binds it)"
fi

echo ""
echo "--- Telemt Container ---"

# --- Check 5: Telemt container ---
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    ok "Container '$CONTAINER_NAME' is running"

    # Network check
    TELEMT_NETS=$(docker inspect "$CONTAINER_NAME" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
    if echo "$TELEMT_NETS" | grep -q "$DOKPLOY_NETWORK"; then
        TELEMT_IP=$(docker inspect "$CONTAINER_NAME" --format "{{(index .NetworkSettings.Networks \"$DOKPLOY_NETWORK\").IPAddress}}" 2>/dev/null)
        ok "On '$DOKPLOY_NETWORK' (IP: $TELEMT_IP)"
    else
        fail "NOT on '$DOKPLOY_NETWORK' — Traefik cannot reach it"
        info "Ensure docker-compose.yml has 'networks: dokploy-network' (external)"
        ERRORS=$((ERRORS + 1))
    fi

    # Label checks
    LABEL_ENABLE=$(docker inspect "$CONTAINER_NAME" --format '{{index .Config.Labels "traefik.enable"}}' 2>/dev/null || echo "")
    LABEL_RULE=$(docker inspect "$CONTAINER_NAME" --format '{{index .Config.Labels "traefik.tcp.routers.telemt-proxy.rule"}}' 2>/dev/null || echo "")
    LABEL_PASSTHROUGH=$(docker inspect "$CONTAINER_NAME" --format '{{index .Config.Labels "traefik.tcp.routers.telemt-proxy.tls.passthrough"}}' 2>/dev/null || echo "")
    LABEL_PORT=$(docker inspect "$CONTAINER_NAME" --format '{{index .Config.Labels "traefik.tcp.services.telemt-proxy.loadbalancer.server.port"}}' 2>/dev/null || echo "")

    if [[ "$LABEL_ENABLE" == "true" ]]; then
        ok "Label: traefik.enable=true"
    else
        fail "Missing label: traefik.enable=true"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ -n "$LABEL_RULE" ]]; then
        ok "Label: TCP router rule = $LABEL_RULE"
    else
        fail "Missing label: traefik.tcp.routers.telemt-proxy.rule"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ "$LABEL_PASSTHROUGH" == "true" ]]; then
        ok "Label: TLS passthrough = true"
    else
        fail "Missing label: tls.passthrough=true"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ "$LABEL_PORT" == "443" ]]; then
        ok "Label: service port = 443"
    else
        fail "Missing label: loadbalancer.server.port=443"
        ERRORS=$((ERRORS + 1))
    fi

    # Config file check
    CONFIG_MOUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/run/telemt/config.toml"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
    if [[ -n "$CONFIG_MOUNT" ]]; then
        ok "Config mounted from: $CONFIG_MOUNT"
    else
        warn "config.toml is not bind-mounted (using image-embedded copy)"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Uptime
    STARTED=$(docker inspect "$CONTAINER_NAME" --format '{{.State.StartedAt}}' 2>/dev/null)
    info "Started: $STARTED"

else
    info "Container '$CONTAINER_NAME' is not running"
    info "Deploy through Dokploy UI or: docker compose up -d --build"
fi

echo ""
echo "--- Cleanup ---"

# --- Check 6: Old deployment ---
OLD_COMPOSE="/etc/dokploy/compose/vpn-telemt-ieinli/code/docker-compose.yml"
if [[ -f "$OLD_COMPOSE" ]]; then
    if grep -q '"443:443"' "$OLD_COMPOSE" 2>/dev/null; then
        warn "Old Dokploy deployment has direct port 443 mapping: $OLD_COMPOSE"
        info "Remove this deployment in Dokploy UI to avoid conflicts"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# --- Check 7: Stale Traefik route file (from old setup.sh) ---
STALE_FILE="/etc/dokploy/traefik/dynamic/telemt-tcp.yml"
if [[ -f "$STALE_FILE" ]]; then
    warn "Stale Traefik route file found: $STALE_FILE"
    info "Docker labels handle routing — this file is unnecessary"
    info "Remove: sudo rm $STALE_FILE"
    WARNINGS=$((WARNINGS + 1))
fi

# --- Summary ---
echo ""
echo "================================================"
echo "  Results"
echo "================================================"
echo ""
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    ok "All checks passed — deployment is healthy"
elif [[ $ERRORS -eq 0 ]]; then
    ok "All critical checks passed ($WARNINGS warning(s))"
else
    fail "$ERRORS critical issue(s), $WARNINGS warning(s)"
fi
echo ""
exit $ERRORS
