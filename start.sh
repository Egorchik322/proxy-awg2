#!/usr/bin/env bash
set -euo pipefail

CONF="${AWG_CONFIG:-/config/awg0.conf}"
IFACE="${AWG_INTERFACE:-$(basename "$CONF" .conf)}"
LAN_CIDR="${LAN_CIDR:-192.168.0.0/24}"

export WG_QUICK_USERSPACE_IMPLEMENTATION=/usr/local/bin/amneziawg-go
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1

REAL_IP="$(command -v ip)"
export REAL_IP

WRAPPER_DIR="/run/awg2-userspace"
mkdir -p "$WRAPPER_DIR"

cat > "$WRAPPER_DIR/ip" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 5 \
   && "$1" == "link" \
   && "$2" == "add" \
   && "$4" == "type" \
   && "$5" == "amneziawg" ]]; then
    echo "Forcing AmneziaWG 2.0 userspace implementation" >&2
    exit 1
fi

exec "$REAL_IP" "$@"
WRAPPER

chmod 755 "$WRAPPER_DIR/ip"
export PATH="/usr/local/bin:$WRAPPER_DIR:/usr/sbin:/usr/bin:/sbin:/bin"

export WG_QUICK_USERSPACE_IMPLEMENTATION=/usr/local/bin/amneziawg-go
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1

cleanup() {
  awg-quick down "$CONF" >/dev/null 2>&1 || true
}

trap cleanup INT TERM EXIT

awg-quick up "$CONF"

ETH_GW="$(ip -4 route show default dev eth0 | awk '{print $3; exit}')"

if [[ -n "$ETH_GW" ]]; then
  ip route replace "$LAN_CIDR" via "$ETH_GW" dev eth0
fi

awg show "$IFACE" || true
ip route get 192.168.0.8 || true

while sleep 3600; do
  awg show "$IFACE" >/dev/null
done
