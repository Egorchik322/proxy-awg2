#!/usr/bin/env bash
set -uo pipefail

CONF="${AWG_CONFIG:-/config/awg0.conf}"
IFACE="${AWG_INTERFACE:-$(basename "$CONF" .conf)}"
LAN_CIDR="${LAN_CIDR:-192.168.0.0/24}"

export WG_QUICK_USERSPACE_IMPLEMENTATION="${WG_QUICK_USERSPACE_IMPLEMENTATION:-amneziawg-go}"
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1

WATCHDOG_ENABLED="${AWG_WATCHDOG_ENABLED:-true}"
WATCHDOG_INTERVAL="${AWG_WATCHDOG_INTERVAL:-15}"
HANDSHAKE_MAX_AGE="${AWG_HANDSHAKE_MAX_AGE:-180}"
WATCHDOG_FAILURES="${AWG_WATCHDOG_FAILURES:-3}"
RECOVERY_COOLDOWN="${AWG_RECOVERY_COOLDOWN:-300}"
STARTUP_GRACE="${AWG_STARTUP_GRACE:-120}"
PROXY_PROBE_TIMEOUT="${AWG_PROXY_PROBE_TIMEOUT:-8}"
PROXY_CANARY_URL="${AWG_PROXY_CANARY_URL:-http://1.1.1.1/}"
MAX_RECOVERIES="${AWG_MAX_RECOVERIES:-3}"
RECOVERY_WINDOW="${AWG_RECOVERY_WINDOW:-3600}"

log() {
  printf 'AWG: %s\n' "$*"
}

restore_lan_route() {
  if ip link show eth0 >/dev/null 2>&1; then
    local eth_gw
    eth_gw="$(ip -4 route show default dev eth0 2>/dev/null | awk '{print $3; exit}')"
    if [[ -n "$eth_gw" ]]; then
      ip route replace "$LAN_CIDR" via "$eth_gw" dev eth0 >/dev/null 2>&1 || true
    fi
  fi
}

cleanup() {
  awg-quick down "$CONF" >/dev/null 2>&1 || true
}

trap 'cleanup' INT TERM EXIT

if ! awg-quick up "$CONF"; then
  log "initial awg-quick up failed"
  exit 1
fi
restore_lan_route

if [[ "$WATCHDOG_ENABLED" != "true" ]]; then
  log "watchdog disabled"
  while sleep 3600; do
    awg show "$IFACE" >/dev/null 2>&1 || exit 1
  done
fi

started_at="$(date +%s)"
failures=0
last_recovery=0
recovery_window_started=0
recoveries=0

read_stats() {
  local dump
  dump="$(awg show "$IFACE" dump 2>/dev/null || true)"
  # dump peer fields: public_key preshared_key endpoint allowed_ips handshake tx rx keepalive
  awk 'NR == 2 { print $5, $6, $7; exit }' <<<"$dump"
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

proxy_probe() {
  local code
  code="$(curl -4 -sS --connect-timeout "$PROXY_PROBE_TIMEOUT" \
    --max-time "$PROXY_PROBE_TIMEOUT" \
    --proxy http://127.0.0.1:38108 \
    --output /dev/null --write-out '%{http_code}' \
    "$PROXY_CANARY_URL" 2>/dev/null || true)"
  [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

recover_awg() {
  log "recovering AWG interface in place"
  awg-quick down "$CONF" >/dev/null 2>&1 || true
  sleep 1
  if ! awg-quick up "$CONF"; then
    log "in-place AWG recovery failed"
    return 1
  fi
  restore_lan_route
  return 0
}

log "started interface=$IFACE watchdog_interval=${WATCHDOG_INTERVAL}s handshake_max_age=${HANDSHAKE_MAX_AGE}s"

while :; do
  now="$(date +%s)"
  uptime=$((now - started_at))
  awg_ok=1
  if ! pgrep -x amneziawg-go >/dev/null 2>&1; then
    awg_ok=0
  fi
  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    awg_ok=0
  fi

  if (( uptime < STARTUP_GRACE )); then
    failures=0
    sleep "$WATCHDOG_INTERVAL"
    continue
  fi

  stats1="$(read_stats)"
  read -r handshake1 tx1 rx1 <<<"$stats1"
  stats_valid=1
  is_number "${handshake1:-}" || stats_valid=0
  is_number "${tx1:-}" || stats_valid=0
  is_number "${rx1:-}" || stats_valid=0

  proxy_ok=0
  if ss -lnt 2>/dev/null | awk '$4 ~ /:38108$/ { found=1 } END { exit(found ? 0 : 1) }'; then
    if proxy_probe; then
      proxy_ok=1
    fi
  fi

  sleep 2
  now="$(date +%s)"
  stats2="$(read_stats)"
  read -r handshake2 tx2 rx2 <<<"$stats2"
  is_number "${handshake2:-}" || stats_valid=0
  is_number "${tx2:-}" || stats_valid=0
  is_number "${rx2:-}" || stats_valid=0

  stale=1
  progress=0
  if (( stats_valid )); then
    if (( handshake2 > 0 && now >= handshake2 && now - handshake2 <= HANDSHAKE_MAX_AGE )); then
      stale=0
    fi
    if (( rx2 > rx1 || tx2 > tx1 )); then
      progress=1
    fi
  fi

  bad=0
  if (( awg_ok == 0 || stats_valid == 0 )); then
    bad=1
  elif (( stale == 1 && progress == 0 && proxy_ok == 0 )); then
    bad=1
  fi

  if (( bad == 0 )); then
    failures=0
    sleep "$WATCHDOG_INTERVAL"
    continue
  fi

  failures=$((failures + 1))
  log "degraded check=$failures/$WATCHDOG_FAILURES awg_ok=$awg_ok stats_valid=$stats_valid stale=$stale progress=$progress proxy=$proxy_ok"
  if (( failures < WATCHDOG_FAILURES )); then
    sleep "$WATCHDOG_INTERVAL"
    continue
  fi

  if (( recovery_window_started == 0 || now - recovery_window_started >= RECOVERY_WINDOW )); then
    recovery_window_started=$now
    recoveries=0
  fi

  if (( last_recovery > 0 && now - last_recovery < RECOVERY_COOLDOWN )); then
    log "recovery suppressed by cooldown"
    sleep "$WATCHDOG_INTERVAL"
    continue
  fi

  if (( recoveries >= MAX_RECOVERIES )); then
    log "recovery limit reached; exiting container for Docker restart"
    exit 1
  fi

  last_recovery=$now
  recoveries=$((recoveries + 1))
  failures=0
  if ! recover_awg; then
    if (( recoveries >= MAX_RECOVERIES )); then
      log "recovery limit reached after failed recovery"
      exit 1
    fi
  fi
  sleep "$WATCHDOG_INTERVAL"
done
