#!/usr/bin/env bash
set -euo pipefail

CONF="${AWG_CONFIG:-/config/awg0.conf}"
IFACE="${AWG_INTERFACE:-$(basename "$CONF" .conf)}"
LAN_CIDR="${LAN_CIDR:-192.168.0.0/24}"

# Keep the implementation in userspace; the host kernel module is not required.
export WG_QUICK_USERSPACE_IMPLEMENTATION="${WG_QUICK_USERSPACE_IMPLEMENTATION:-amneziawg-go}"
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1

cleanup() {
  awg-quick down "$CONF" >/dev/null 2>&1 || true
}

trap cleanup INT TERM EXIT

awg-quick up "$CONF"

# Keep LAN replies outside the VPN when a Docker bridge gateway exists.
if ip link show eth0 >/dev/null 2>&1; then
  ETH_GW="$(ip -4 route show default dev eth0 | awk '{print $3; exit}')"
  if [[ -n "$ETH_GW" ]]; then
    ip route replace "$LAN_CIDR" via "$ETH_GW" dev eth0
  fi
fi

awg show "$IFACE" || true
ip route get 192.168.0.8 >/dev/null 2>&1 || true

while sleep 3600; do
  awg show "$IFACE" >/dev/null
done
