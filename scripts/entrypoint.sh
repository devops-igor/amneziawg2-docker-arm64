#!/bin/bash
# =============================================================================
# AmneziaWG 2.0 Docker Client — Entrypoint Script
# =============================================================================
# Starts the AmneziaWG client in a Docker container.
# awg-quick handles tunnel setup, routing, and its own kill-switch.
# This script handles DNS (since resolvconf is stubbed) and graceful shutdown.
#
# Usage:
#   Mount your config: -v /path/to/amneziawg.conf:/config/amneziawg.conf
#   Required sysctls:  --sysctl net.ipv4.ip_forward=1
#                      --sysctl net.ipv4.conf.all.src_valid_mark=1
#   Required caps:     --cap-add NET_ADMIN
#   Required device:   --device /dev/net/tun:/dev/net/tun
# =============================================================================

set -euo pipefail

CONFIG_FILE="/config/amneziawg.conf"

# --- Validation -----------------------------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config not found at $CONFIG_FILE"
    echo "Mount your AmneziaWG config with: -v /path/to/config:/config/amneziawg.conf"
    exit 1
fi

# Check for TUN device (required for AmneziaWG)
if [ ! -c /dev/net/tun ]; then
    echo "ERROR: /dev/net/tun not found."
    echo "Run Docker with: --device /dev/net/tun:/dev/net/tun"
    echo "Also ensure the host has the tun module loaded: sudo modprobe tun"
    exit 1
fi

if ! grep -q '^\[Interface\]' "$CONFIG_FILE"; then
    echo "ERROR: Config must contain [Interface] section"
    exit 1
fi

if ! grep -q '^\[Peer\]' "$CONFIG_FILE"; then
    echo "ERROR: Config must contain at least one [Peer] section"
    exit 1
fi

# Warn about required sysctls (container must be run with these)
for param in net.ipv4.ip_forward net.ipv4.conf.all.src_valid_mark; do
    val=$(sysctl -n "$param" 2>/dev/null || echo "0")
    if [ "$val" != "1" ]; then
        echo "WARNING: $param is not set to 1."
        echo "         Run Docker with: --sysctl $param=1"
    fi
done

# --- Show config info (sanitized — no PrivateKey printed) -----------------
echo "=== AmneziaWG Client Config ==="
echo "Config file: $CONFIG_FILE"
echo "Interface section found: $(grep -c '^\[Interface\]' "$CONFIG_FILE")"
echo "Peer section(s) found: $(grep -c '^\[Peer\]' "$CONFIG_FILE")"
echo "AmneziaWG 2.0 params detected:"
grep -E '^[ \t]*(Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5])[ \t]*=' "$CONFIG_FILE" || echo "  (none — using standard WireGuard or server defaults)"
echo "================================"

# --- Graceful Shutdown Trap -----------------------------------------------
cleanup() {
    echo "Caught SIGTERM/SIGINT — shutting down AmneziaWG..."
    awg-quick down "$CONFIG_FILE" 2>/dev/null || true
    echo "Shutdown complete."
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- Start AmneziaWG ------------------------------------------------------
echo "Starting AmneziaWG client..."
awg-quick up "$CONFIG_FILE"

# --- Configure DNS manually (resolvconf is stubbed) -----------------------
DNS_SERVERS=$(sed -n '/^\[Interface\]/,/^\[/{/^[Dd][Nn][Ss][ \t]*=/p}' "$CONFIG_FILE" | sed 's/^[Dd][Nn][Ss][ \t]*=[ \t]*//;s/,/ /g')
if [ -n "$DNS_SERVERS" ]; then
    echo "Configuring DNS: $DNS_SERVERS"
    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    > /etc/resolv.conf
    for dns in $DNS_SERVERS; do
        echo "nameserver $dns" >> /etc/resolv.conf
    done
    echo "DNS configured successfully."
else
    echo "No DNS servers found in config, skipping DNS setup."
fi

# --- Verify tunnel is up ---------------------------------------------------
sleep 1
if ! ip link show type awg 2>/dev/null && ! ip link show 2>/dev/null | grep -q '^awg'; then
    echo "ERROR: AmneziaWG interface failed to come up."
    echo "Check 'awg show' and 'ip link' for details."
    exit 1
fi

echo "AmneziaWG interface is up. Kill-switch is handled by awg-quick."
echo "Container staying alive — logs follow."

# Drop privileges for the long-running process if running as root
if [ "$(id -u)" -eq 0 ] && id amneziawg >/dev/null 2>&1; then
    exec su -s /bin/bash amneziawg -c "exec tail -f /dev/null"
else
    exec tail -f /dev/null
fi
