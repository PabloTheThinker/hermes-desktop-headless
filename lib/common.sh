#!/usr/bin/env bash
# Shared helpers for hermes-desktop-headless. Sourced only — not executed.
# shellcheck disable=SC2034

: "${HD_DISPLAY:=99}"
: "${HD_GEOMETRY:=1920x1080x24}"
: "${HD_VNC_PORT:=5901}"
: "${HD_NOVNC_PORT:=6080}"
: "${HD_BIND:=127.0.0.1}"
: "${HD_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/hermes-desktop-headless}"
: "${HD_HERMES_CMD:=hermes desktop --skip-build}"
: "${HD_NO_SANDBOX:=1}"
: "${HD_VNC_PASSWORD_FILE:=}"
: "${HD_USER_DATA:=${HERMES_DESKTOP_USER_DATA_DIR:-$HOME/.config/Hermes}}"
: "${HD_NOVNC_WEB:=/usr/share/novnc}"
: "${HD_WAIT_HERMES_SEC:=45}"

hd_need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    return 1
  }
}

hd_doctor() {
  local missing=0
  for b in Xvfb x11vnc websockify fluxbox scrot; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "ok  $b → $(command -v "$b")"
    else
      echo "MISS $b"
      missing=1
    fi
  done
  if [[ -d "$HD_NOVNC_WEB" ]]; then
    echo "ok  noVNC web → $HD_NOVNC_WEB"
  else
    echo "MISS noVNC web root ($HD_NOVNC_WEB)"
    missing=1
  fi
  if command -v hermes >/dev/null 2>&1; then
    echo "ok  hermes → $(command -v hermes)"
    hermes --version 2>/dev/null | head -3 || true
  else
    echo "MISS hermes CLI on PATH"
    missing=1
  fi
  echo "display candidate :$HD_DISPLAY  bind=$HD_BIND  vnc=$HD_VNC_PORT  novnc=$HD_NOVNC_PORT"
  echo "state dir $HD_STATE_DIR"
  return "$missing"
}

hd_mkdirs() {
  mkdir -p "$HD_STATE_DIR"/{logs,run}
}

hd_pidfile() { echo "$HD_STATE_DIR/run/$1.pid"; }
hd_logfile() { echo "$HD_STATE_DIR/logs/$1.log"; }

hd_is_alive() {
  local pf pid
  pf="$(hd_pidfile "$1")"
  [[ -f "$pf" ]] || return 1
  pid="$(cat "$pf" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

hd_kill_pidfile() {
  local name="$1" pf pid
  pf="$(hd_pidfile "$name")"
  if [[ -f "$pf" ]]; then
    pid="$(cat "$pf" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # give it a moment, then force
      for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pf"
  fi
}

hd_clear_singleton() {
  local lock="$HD_USER_DATA/SingletonLock" target pid
  mkdir -p "$HD_USER_DATA"
  if [[ -e "$lock" || -L "$lock" ]]; then
    target="$(readlink "$lock" 2>/dev/null || true)"
    pid="${target##*-}"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      echo "Hermes Desktop already running (pid $pid) — leaving SingletonLock alone"
      return 0
    fi
    echo "clearing stale Electron singleton (was: ${target:-unknown})"
    rm -f "$HD_USER_DATA/SingletonLock" \
          "$HD_USER_DATA/SingletonCookie" \
          "$HD_USER_DATA/SingletonSocket"
  fi
}

hd_export_display() {
  export DISPLAY=":${HD_DISPLAY}"
  export XAUTHORITY="${XAUTHORITY:-$HD_STATE_DIR/run/xauth}"
  # GPU-less virtual framebuffer: avoid GPU process crashes
  export HERMES_DESKTOP_DISABLE_GPU="${HERMES_DESKTOP_DISABLE_GPU:-1}"
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-x11}"
}

hd_start_xvfb() {
  if hd_is_alive xvfb; then
    echo "Xvfb already running (pid $(cat "$(hd_pidfile xvfb)"))"
    return 0
  fi
  if [[ -e "/tmp/.X${HD_DISPLAY}-lock" ]]; then
    # orphan lock?
    if ! pgrep -af "Xvfb :${HD_DISPLAY}" >/dev/null 2>&1; then
      rm -f "/tmp/.X${HD_DISPLAY}-lock" "/tmp/.X11-unix/X${HD_DISPLAY}" 2>/dev/null || true
    else
      echo "display :${HD_DISPLAY} already in use by another Xvfb" >&2
      return 1
    fi
  fi
  hd_need Xvfb
  local log; log="$(hd_logfile xvfb)"
  # shellcheck disable=SC2086
  Xvfb ":${HD_DISPLAY}" -screen 0 "$HD_GEOMETRY" -ac -nolisten tcp \
    >"$log" 2>&1 &
  echo $! >"$(hd_pidfile xvfb)"
  sleep 0.4
  if ! hd_is_alive xvfb; then
    echo "Xvfb failed to start — see $log" >&2
    return 1
  fi
  echo "Xvfb :${HD_DISPLAY} up (pid $(cat "$(hd_pidfile xvfb)"))"
}

hd_start_dbus_wm() {
  hd_export_display
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if command -v dbus-launch >/dev/null 2>&1; then
      # shellcheck disable=SC2046
      eval "$(dbus-launch --sh-syntax)"
      echo "$DBUS_SESSION_BUS_ADDRESS" >"$HD_STATE_DIR/run/dbus.address"
      echo "$DBUS_SESSION_BUS_PID" >"$(hd_pidfile dbus)"
      echo "dbus session bus pid $DBUS_SESSION_BUS_PID"
    fi
  fi
  if hd_is_alive fluxbox; then
    echo "fluxbox already running"
    return 0
  fi
  hd_need fluxbox
  local log; log="$(hd_logfile fluxbox)"
  fluxbox >"$log" 2>&1 &
  echo $! >"$(hd_pidfile fluxbox)"
  sleep 0.3
  echo "fluxbox up (pid $(cat "$(hd_pidfile fluxbox)"))"
}

hd_start_hermes() {
  hd_export_display
  hd_clear_singleton
  if pgrep -f '/apps/desktop/release/linux-unpacked/Hermes|electron .*apps/desktop' >/dev/null 2>&1; then
    echo "Hermes Desktop process already present"
    pgrep -af 'Hermes|electron' | head -5 || true
    return 0
  fi
  if ! command -v hermes >/dev/null 2>&1; then
    echo "hermes CLI not on PATH" >&2
    return 1
  fi
  local log; log="$(hd_logfile hermes-desktop)"
  # Optional electron flags via hermes config; we also set env for GPU off.
  # --no-sandbox: hermes CLI often injects this when AppArmor blocks userns.
  # Running under virtual display as the same user that owns HERMES_HOME.
  # shellcheck disable=SC2086
  nohup env DISPLAY=":$HD_DISPLAY" \
    HERMES_DESKTOP_DISABLE_GPU=1 \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
    $HD_HERMES_CMD \
    >"$log" 2>&1 &
  echo $! >"$(hd_pidfile hermes-desktop)"
  echo "hermes desktop launch pid $(cat "$(hd_pidfile hermes-desktop)") - log $log"

  local i
  for i in $(seq 1 "$HD_WAIT_HERMES_SEC"); do
    if pgrep -f 'linux-unpacked/Hermes' >/dev/null 2>&1; then
      echo "Hermes Electron binary is running"
      return 0
    fi
    # hermes CLI may still be packaging/starting
    if ! hd_is_alive hermes-desktop && [[ "$i" -gt 5 ]]; then
      echo "launcher exited early — tail log:" >&2
      tail -n 40 "$log" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "timeout waiting for Hermes Electron — tail log:" >&2
  tail -n 60 "$log" >&2 || true
  return 1
}

hd_start_vnc() {
  if [[ "${HD_SKIP_VNC:-0}" == "1" ]]; then
    echo "skipping VNC (HD_SKIP_VNC=1)"
    return 0
  fi
  if hd_is_alive x11vnc; then
    echo "x11vnc already running"
    return 0
  fi
  hd_need x11vnc
  hd_export_display
  local log auth_args=()
  log="$(hd_logfile x11vnc)"
  if [[ -n "$HD_VNC_PASSWORD_FILE" && -f "$HD_VNC_PASSWORD_FILE" ]]; then
    auth_args=(-rfbauth "$HD_VNC_PASSWORD_FILE")
  else
    # localhost-only default: no password. Refuse open bind without password file.
    if [[ "$HD_BIND" != "127.0.0.1" && "$HD_BIND" != "localhost" ]]; then
      echo "refusing non-localhost VNC bind without HD_VNC_PASSWORD_FILE" >&2
      return 1
    fi
    auth_args=(-nopw)
  fi
  x11vnc -display ":$HD_DISPLAY" \
    -rfbport "$HD_VNC_PORT" \
    -listen "$HD_BIND" \
    -forever -shared -noxdamage -repeat \
    "${auth_args[@]}" \
    >"$log" 2>&1 &
  echo $! >"$(hd_pidfile x11vnc)"
  sleep 0.4
  if ! hd_is_alive x11vnc; then
    echo "x11vnc failed — see $log" >&2
    tail -n 30 "$log" >&2 || true
    return 1
  fi
  echo "x11vnc on ${HD_BIND}:${HD_VNC_PORT} (pid $(cat "$(hd_pidfile x11vnc)"))"
}

hd_start_novnc() {
  if [[ "${HD_SKIP_VNC:-0}" == "1" ]]; then
    return 0
  fi
  if hd_is_alive novnc; then
    echo "noVNC already running"
    return 0
  fi
  hd_need websockify
  [[ -d "$HD_NOVNC_WEB" ]] || {
    echo "noVNC web root missing: $HD_NOVNC_WEB" >&2
    return 1
  }
  local log; log="$(hd_logfile novnc)"
  websockify --web="$HD_NOVNC_WEB" \
    "${HD_BIND}:${HD_NOVNC_PORT}" \
    "127.0.0.1:${HD_VNC_PORT}" \
    >"$log" 2>&1 &
  echo $! >"$(hd_pidfile novnc)"
  sleep 0.3
  if ! hd_is_alive novnc; then
    echo "websockify/noVNC failed — see $log" >&2
    tail -n 30 "$log" >&2 || true
    return 1
  fi
  echo "noVNC on http://${HD_BIND}:${HD_NOVNC_PORT}/vnc.html (pid $(cat "$(hd_pidfile novnc)"))"
}

hd_print_urls() {
  cat <<EOF
Display   : :${HD_DISPLAY}
VNC       : ${HD_BIND}:${HD_VNC_PORT}
noVNC     : http://${HD_BIND}:${HD_NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote
SSH tunnel example:
  ssh -N -L ${HD_NOVNC_PORT}:127.0.0.1:${HD_NOVNC_PORT} -L ${HD_VNC_PORT}:127.0.0.1:${HD_VNC_PORT} user@host
Then open: http://127.0.0.1:${HD_NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote
EOF
}

hd_start() {
  local foreground=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --foreground) foreground=1; shift ;;
      --no-vnc) HD_SKIP_VNC=1; shift ;;
      --bind) HD_BIND="$2"; shift 2 ;;
      *) echo "unknown start flag: $1" >&2; return 1 ;;
    esac
  done

  hd_mkdirs
  hd_doctor >/dev/null || {
    echo "doctor failed — install missing deps (see: hermes-desktop-headless doctor)" >&2
    hd_doctor || true
    return 1
  }

  hd_start_xvfb
  hd_start_dbus_wm
  hd_start_hermes
  hd_start_vnc
  hd_start_novnc
  hd_print_urls
  date -u +"%Y-%m-%dT%H:%M:%SZ started" >>"$HD_STATE_DIR/logs/lifecycle.log"

  if [[ "$foreground" -eq 1 ]]; then
    echo "foreground mode — Ctrl-C stops the stack"
    trap 'hd_stop' INT TERM
    while hd_is_alive xvfb; do sleep 2; done
  fi
}

hd_stop() {
  hd_mkdirs
  # order: app → vnc → wm → xvfb
  hd_kill_pidfile hermes-desktop
  # also kill Electron if hermes launcher already exited
  pkill -f 'linux-unpacked/Hermes' 2>/dev/null || true
  hd_kill_pidfile novnc
  hd_kill_pidfile x11vnc
  hd_kill_pidfile fluxbox
  if [[ -f "$(hd_pidfile dbus)" ]]; then
    hd_kill_pidfile dbus
  fi
  hd_kill_pidfile xvfb
  # orphan Xvfb on our display
  pkill -f "Xvfb :${HD_DISPLAY}" 2>/dev/null || true
  rm -f "/tmp/.X${HD_DISPLAY}-lock" 2>/dev/null || true
  hd_clear_singleton || true
  date -u +"%Y-%m-%dT%H:%M:%SZ stopped" >>"$HD_STATE_DIR/logs/lifecycle.log"
  echo "stopped"
}

hd_status() {
  hd_mkdirs
  for n in xvfb dbus fluxbox hermes-desktop x11vnc novnc; do
    if hd_is_alive "$n"; then
      echo "UP   $n pid=$(cat "$(hd_pidfile "$n")")"
    else
      echo "DOWN $n"
    fi
  done
  if pgrep -f 'linux-unpacked/Hermes' >/dev/null 2>&1; then
    echo "UP   electron (pgrep)"
    pgrep -af 'linux-unpacked/Hermes' | head -3
  else
    echo "DOWN electron (pgrep)"
  fi
  [[ -e "/tmp/.X11-unix/X${HD_DISPLAY}" ]] && echo "X socket :$HD_DISPLAY present" || echo "X socket :$HD_DISPLAY missing"
  hd_print_urls
}

hd_screenshot() {
  hd_export_display
  hd_need scrot
  local out="${1:-$HD_STATE_DIR/logs/screenshot-$(date -u +%Y%m%dT%H%M%SZ).png}"
  mkdir -p "$(dirname "$out")"
  # scrot needs the display live
  scrot -o "$out"
  echo "$out"
  # also copy into project docs if running from a checkout with docs/screenshots
  if [[ -d "${ROOT:-}/docs/screenshots" ]]; then
    cp -f "$out" "$ROOT/docs/screenshots/$(basename "$out")" 2>/dev/null || true
  fi
}
