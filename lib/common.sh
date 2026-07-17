#!/usr/bin/env bash
# Shared library for hermes-desktop-headless (sourced, not executed).
# Portable across Debian/Ubuntu, Fedora/RHEL, Arch (path + package discovery).
# shellcheck shell=bash disable=SC2034

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
: "${HD_DISPLAY:=99}"
: "${HD_GEOMETRY:=1920x1080x24}"
: "${HD_VNC_PORT:=5901}"
: "${HD_NOVNC_PORT:=6080}"
: "${HD_BIND:=127.0.0.1}"
: "${HD_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/hermes-desktop-headless}"
: "${HD_HERMES_CMD:=hermes desktop --skip-build}"
: "${HD_VNC_PASSWORD_FILE:=}"
: "${HD_USER_DATA:=${HERMES_DESKTOP_USER_DATA_DIR:-$HOME/.config/Hermes}}"
: "${HD_NOVNC_WEB:=}"
: "${HD_WM:=}"
: "${HD_WAIT_HERMES_SEC:=45}"
: "${HD_SKIP_VNC:=0}"
: "${HD_LOG_LEVEL:=info}" # debug|info|warn
# Pointer fidelity for noVNC drag (session tiling). Override with HD_X11VNC_EXTRA.
: "${HD_X11VNC_EXTRA:=}"
: "${HD_POINTER_MODE:=1}"
: "${HD_VNC_DEFER_MS:=1}"
: "${HD_VNC_WAIT_MS:=5}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
hd_log() {
  local level="$1"; shift
  case "$level" in
    debug) [[ "${HD_LOG_LEVEL}" == debug ]] || return 0 ;;
    info|warn|error) ;;
    *) level=info ;;
  esac
  printf '[%s] %s\n' "$level" "$*" >&2
}

hd_die() { hd_log error "$*"; return 1; }

# ---------------------------------------------------------------------------
# Paths / process helpers
# ---------------------------------------------------------------------------
hd_mkdirs() { mkdir -p "$HD_STATE_DIR"/{logs,run}; }

hd_pidfile() { printf '%s/run/%s.pid\n' "$HD_STATE_DIR" "$1"; }
hd_logfile() { printf '%s/logs/%s.log\n' "$HD_STATE_DIR" "$1"; }

hd_is_alive() {
  local pf pid
  pf="$(hd_pidfile "$1")"
  [[ -f "$pf" ]] || return 1
  pid="$(<"$pf")"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

hd_read_pid() {
  local pf; pf="$(hd_pidfile "$1")"
  [[ -f "$pf" ]] && cat "$pf" || true
}

hd_spawn() {
  # hd_spawn <name> <command...>  — run in background, record pid + log
  local name="$1"; shift
  local log; log="$(hd_logfile "$name")"
  hd_log debug "spawn $name: $*"
  nohup "$@" >"$log" 2>&1 &
  echo $! >"$(hd_pidfile "$name")"
}

hd_kill_pidfile() {
  local name="$1" pf pid
  pf="$(hd_pidfile "$name")"
  [[ -f "$pf" ]] || return 0
  pid="$(<"$pf")"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.15
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pf"
}

hd_wait_until() {
  # hd_wait_until <seconds> <message> <command...>
  local secs="$1" msg="$2"; shift 2
  local i
  for ((i = 1; i <= secs * 5; i++)); do
    if "$@"; then return 0; fi
    sleep 0.2
  done
  hd_log error "timeout waiting for: $msg"
  return 1
}

hd_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Distro / dependency resolution
# ---------------------------------------------------------------------------
hd_os_id() {
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && . /etc/os-release
  printf '%s\n' "${ID:-unknown}"
}

hd_resolve_novnc_web() {
  if [[ -n "${HD_NOVNC_WEB}" && -d "${HD_NOVNC_WEB}" ]]; then
    printf '%s\n' "$HD_NOVNC_WEB"
    return 0
  fi
  local p
  for p in \
    /usr/share/novnc \
    /usr/share/webapps/novnc \
    /usr/local/share/novnc \
    "$HOME/.local/share/novnc"
  do
    if [[ -d "$p" && ( -f "$p/vnc.html" || -f "$p/vnc_lite.html" ) ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

hd_resolve_websockify() {
  if hd_have websockify; then
    printf '%s\n' websockify
    return 0
  fi
  if hd_have python3 && python3 -c 'import websockify' 2>/dev/null; then
    printf '%s\n' 'python3 -m websockify'
    return 0
  fi
  return 1
}

hd_resolve_wm() {
  local preferred="${HD_WM:-}" c
  if [[ -n "$preferred" ]]; then
    hd_have "$preferred" && { printf '%s\n' "$preferred"; return 0; }
  fi
  for c in fluxbox openbox icewm matchbox-window-manager; do
    if hd_have "$c"; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

hd_resolve_screenshot() {
  if hd_have scrot; then printf '%s\n' scrot; return 0; fi
  if hd_have import; then printf '%s\n' import; return 0; fi # ImageMagick
  if hd_have gnome-screenshot; then printf '%s\n' gnome-screenshot; return 0; fi
  return 1
}

hd_package_hints() {
  local id; id="$(hd_os_id)"
  case "$id" in
    ubuntu|debian|linuxmint|pop|raspbian)
      echo "sudo apt-get install -y xvfb x11vnc novnc websockify fluxbox scrot dbus-x11 xdotool"
      ;;
    fedora|rhel|centos|rocky|almalinux)
      echo "sudo dnf install -y xorg-x11-server-Xvfb x11vnc novnc python3-websockify fluxbox scrot dbus-x11 xdotool"
      ;;
    arch|manjaro|endeavouros)
      echo "sudo pacman -S --needed xorg-server-xvfb x11vnc novnc python-websockify fluxbox scrot dbus xdotool"
      ;;
    opensuse*|sles)
      echo "sudo zypper install -y xorg-x11-server-Xvfb x11vnc novnc python3-websockify fluxbox scrot dbus-1-x11 xdotool"
      ;;
    *)
      echo "# Install: Xvfb, x11vnc, noVNC, websockify, a WM (fluxbox/openbox), scrot, dbus-x11, xdotool (for split CLI)"
      ;;
  esac
  echo "# Hermes CLI must be on PATH: https://hermes-agent.nousresearch.com/"
}

hd_doctor() {
  local hints=0 missing=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-hints) hints=1; shift ;;
      *) shift ;;
    esac
  done

  local b
  for b in Xvfb x11vnc; do
    if hd_have "$b"; then
      echo "ok   $b -> $(command -v "$b")"
    else
      echo "MISS $b"
      missing=1
    fi
  done

  if hd_resolve_websockify >/dev/null; then
    echo "ok   websockify -> $(hd_resolve_websockify)"
  else
    echo "MISS websockify (or python3 -m websockify)"
    missing=1
  fi

  if hd_resolve_wm >/dev/null; then
    echo "ok   window manager -> $(hd_resolve_wm)"
  else
    echo "MISS window manager (fluxbox|openbox|icewm)"
    missing=1
  fi

  if novnc_web="$(hd_resolve_novnc_web 2>/dev/null)"; then
    echo "ok   noVNC web -> $novnc_web"
  else
    echo "MISS noVNC web root (expected /usr/share/novnc or set HD_NOVNC_WEB)"
    missing=1
  fi

  if hd_resolve_screenshot >/dev/null; then
    echo "ok   screenshot -> $(hd_resolve_screenshot)"
  else
    echo "WARN screenshot tool missing (scrot|import) - optional"
  fi

  if hd_have hermes; then
    echo "ok   hermes -> $(command -v hermes)"
    hermes --version 2>/dev/null | head -3 || true
  else
    echo "MISS hermes CLI on PATH"
    missing=1
  fi

  if hd_have dbus-launch; then
    echo "ok   dbus-launch -> $(command -v dbus-launch)"
  else
    echo "WARN dbus-launch missing (recommended)"
  fi

  echo "plan display=:${HD_DISPLAY} bind=${HD_BIND} vnc=${HD_VNC_PORT} novnc=${HD_NOVNC_PORT}"
  echo "plan state=${HD_STATE_DIR} os=$(hd_os_id)"

  if [[ "$hints" -eq 1 ]] || [[ "$missing" -ne 0 ]]; then
    echo "--- install hints ---"
    hd_package_hints
  fi
  return "$missing"
}

# ---------------------------------------------------------------------------
# Runtime env
# ---------------------------------------------------------------------------
hd_export_display() {
  export DISPLAY=":${HD_DISPLAY}"
  export XAUTHORITY="${XAUTHORITY:-$HD_STATE_DIR/run/xauth}"
  export HERMES_DESKTOP_DISABLE_GPU="${HERMES_DESKTOP_DISABLE_GPU:-1}"
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-x11}"
  # Persist for screenshot/status in other shells
  {
    printf 'export DISPLAY=%q\n' "$DISPLAY"
    printf 'export XAUTHORITY=%q\n' "$XAUTHORITY"
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
      printf 'export DBUS_SESSION_BUS_ADDRESS=%q\n' "$DBUS_SESSION_BUS_ADDRESS"
    fi
  } >"$HD_STATE_DIR/run/env.sh"
}

hd_load_runtime_env() {
  # shellcheck disable=SC1091
  [[ -f "$HD_STATE_DIR/run/env.sh" ]] && . "$HD_STATE_DIR/run/env.sh"
}

hd_is_loopback_bind() {
  case "$HD_BIND" in
    127.0.0.1|localhost|::1) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Electron singleton
# ---------------------------------------------------------------------------
hd_clear_singleton() {
  local lock="$HD_USER_DATA/SingletonLock" target pid
  mkdir -p "$HD_USER_DATA"
  if [[ -e "$lock" || -L "$lock" ]]; then
    target="$(readlink "$lock" 2>/dev/null || true)"
    pid="${target##*-}"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      hd_log info "Hermes Desktop already running (pid $pid); leaving SingletonLock"
      return 0
    fi
    hd_log info "clearing stale Electron singleton (${target:-unknown})"
    rm -f "$HD_USER_DATA/SingletonLock" \
          "$HD_USER_DATA/SingletonCookie" \
          "$HD_USER_DATA/SingletonSocket"
  fi
}

# Kill only Hermes Electron processes bound to our DISPLAY (not every Hermes on the host).
hd_proc_display() {
  # best-effort; other users' /proc/*/environ may be unreadable
  local pid="$1" envf="/proc/$pid/environ"
  [[ -r "$envf" ]] || return 0
  tr '\0' '\n' <"$envf" 2>/dev/null | sed -n 's/^DISPLAY=//p' | head -1 || true
}

hd_kill_electron_on_display() {
  local pid disp
  for pid in $(pgrep -f 'linux-unpacked/Hermes' 2>/dev/null || true); do
    disp="$(hd_proc_display "$pid")"
    if [[ "$disp" == ":${HD_DISPLAY}" || "$disp" == "${HD_DISPLAY}" ]]; then
      hd_log debug "stopping electron pid $pid on DISPLAY=$disp"
      kill "$pid" 2>/dev/null || true
    fi
  done
  sleep 0.3
  for pid in $(pgrep -f 'linux-unpacked/Hermes' 2>/dev/null || true); do
    disp="$(hd_proc_display "$pid")"
    if [[ "$disp" == ":${HD_DISPLAY}" || "$disp" == "${HD_DISPLAY}" ]]; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

hd_electron_on_display() {
  local pid disp
  for pid in $(pgrep -f 'linux-unpacked/Hermes' 2>/dev/null || true); do
    disp="$(hd_proc_display "$pid")"
    if [[ "$disp" == ":${HD_DISPLAY}" || "$disp" == "${HD_DISPLAY}" ]]; then
      return 0
    fi
  done
  # Fallback: any Hermes binary if our launcher is alive (environ unreadable)
  if hd_is_alive hermes-desktop && pgrep -f 'linux-unpacked/Hermes' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Stack components
# ---------------------------------------------------------------------------
hd_start_xvfb() {
  if hd_is_alive xvfb; then
    hd_log info "Xvfb already up (pid $(hd_read_pid xvfb))"
    return 0
  fi
  if [[ -e "/tmp/.X${HD_DISPLAY}-lock" ]]; then
    if ! pgrep -af "Xvfb :${HD_DISPLAY}" >/dev/null 2>&1; then
      rm -f "/tmp/.X${HD_DISPLAY}-lock" "/tmp/.X11-unix/X${HD_DISPLAY}" 2>/dev/null || true
    else
      hd_die "display :${HD_DISPLAY} already in use"
    fi
  fi
  hd_have Xvfb || hd_die "Xvfb missing"
  hd_spawn xvfb Xvfb ":${HD_DISPLAY}" -screen 0 "$HD_GEOMETRY" -ac -nolisten tcp
  hd_wait_until 5 "Xvfb socket" test -e "/tmp/.X11-unix/X${HD_DISPLAY}" \
    || hd_die "Xvfb failed - see $(hd_logfile xvfb)"
  hd_log info "Xvfb :${HD_DISPLAY} up (pid $(hd_read_pid xvfb))"
}

hd_start_dbus_wm() {
  hd_export_display
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && hd_have dbus-launch; then
    # shellcheck disable=SC2046
    eval "$(dbus-launch --sh-syntax)"
    printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" >"$HD_STATE_DIR/run/dbus.address"
    printf '%s\n' "$DBUS_SESSION_BUS_PID" >"$(hd_pidfile dbus)"
    hd_log info "dbus session pid $DBUS_SESSION_BUS_PID"
    hd_export_display
  fi

  if hd_is_alive wm; then
    hd_log info "window manager already up"
    return 0
  fi
  local wm; wm="$(hd_resolve_wm)" || hd_die "no window manager (install fluxbox/openbox/icewm)"
  # matchbox uses a long binary name
  case "$wm" in
    matchbox-window-manager) hd_spawn wm matchbox-window-manager -use_titlebar no ;;
    *) hd_spawn wm "$wm" ;;
  esac
  sleep 0.25
  hd_log info "wm $wm up (pid $(hd_read_pid wm))"
}

hd_start_hermes() {
  hd_export_display
  hd_clear_singleton
  if hd_electron_on_display; then
    hd_log info "Hermes Electron already on DISPLAY=:${HD_DISPLAY}"
    return 0
  fi
  hd_have hermes || hd_die "hermes CLI not on PATH"

  local log; log="$(hd_logfile hermes-desktop)"
  # shellcheck disable=SC2086
  nohup env DISPLAY=":$HD_DISPLAY" \
    HERMES_DESKTOP_DISABLE_GPU=1 \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
    $HD_HERMES_CMD \
    >"$log" 2>&1 &
  echo $! >"$(hd_pidfile hermes-desktop)"
  hd_log info "hermes desktop launcher pid $(hd_read_pid hermes-desktop)"

  local i
  for ((i = 1; i <= HD_WAIT_HERMES_SEC; i++)); do
    if hd_electron_on_display; then
      hd_log info "Hermes Electron running on :${HD_DISPLAY}"
      return 0
    fi
    if ! hd_is_alive hermes-desktop && [[ "$i" -gt 5 ]]; then
      hd_log error "launcher exited early - tail $(hd_logfile hermes-desktop):"
      tail -n 40 "$log" >&2 || true
      return 1
    fi
    sleep 1
  done
  hd_log error "timeout waiting for Electron - tail $(hd_logfile hermes-desktop):"
  tail -n 60 "$log" >&2 || true
  return 1
}

hd_start_vnc() {
  [[ "$HD_SKIP_VNC" == "1" ]] && { hd_log info "skip VNC"; return 0; }
  if hd_is_alive x11vnc; then
    hd_log info "x11vnc already up"
    return 0
  fi
  hd_have x11vnc || hd_die "x11vnc missing"
  hd_export_display

  local auth_args=()
  if [[ -n "$HD_VNC_PASSWORD_FILE" && -f "$HD_VNC_PASSWORD_FILE" ]]; then
    auth_args=(-rfbauth "$HD_VNC_PASSWORD_FILE")
  else
    hd_is_loopback_bind || hd_die "non-localhost bind requires HD_VNC_PASSWORD_FILE"
    auth_args=(-nopw)
  fi

  # Pointer path tuned for noVNC drag (session tiles / Open-in-split gestures):
  # -always_inject  : deliver clicks even when dx=dy=0 (menu clicks, slow drags)
  # -pointer_mode 1 : smoother motion sampling (less "stuck" drags)
  # -cursor most    : real X cursors so targets are visible over VNC
  # -defer 1 -wait 5: low latency updates so drop targets track the pointer
  # -wait_ui 0.5    : poll faster while UI input is active
  # shellcheck disable=SC2086
  hd_spawn x11vnc x11vnc \
    -display ":$HD_DISPLAY" \
    -rfbport "$HD_VNC_PORT" \
    -listen "$HD_BIND" \
    -forever -shared -noxdamage -repeat \
    -always_inject \
    -pointer_mode "$HD_POINTER_MODE" \
    -cursor most \
    -defer "$HD_VNC_DEFER_MS" \
    -wait "$HD_VNC_WAIT_MS" \
    -wait_ui 0.5 \
    "${auth_args[@]}" \
    $HD_X11VNC_EXTRA

  hd_wait_until 5 "x11vnc" hd_is_alive x11vnc \
    || { tail -n 30 "$(hd_logfile x11vnc)" >&2; hd_die "x11vnc failed"; }
  hd_log info "x11vnc ${HD_BIND}:${HD_VNC_PORT} (pid $(hd_read_pid x11vnc)) [pointer-fidelity]"
}

hd_novnc_query() {
  # Optimal noVNC client params for drag/drop tiling:
  # resize=remote  — 1:1 coords (scale mode breaks drop geometry)
  # quality=9 compression=0 — fewer smear/ghost frames during drag
  # show_dot=1 — local cursor for hit-testing
  printf 'autoconnect=1&resize=remote&quality=9&compression=0&show_dot=1'
}

hd_novnc_url() {
  printf 'http://%s:%s/vnc.html?%s\n' "$HD_BIND" "$HD_NOVNC_PORT" "$(hd_novnc_query)"
}

hd_start_novnc() {
  [[ "$HD_SKIP_VNC" == "1" ]] && return 0
  if hd_is_alive novnc; then
    hd_log info "noVNC already up"
    return 0
  fi
  local wscmd web
  wscmd="$(hd_resolve_websockify)" || hd_die "websockify missing"
  web="$(hd_resolve_novnc_web)" || hd_die "noVNC web root missing"

  # shellcheck disable=SC2086
  hd_spawn novnc $wscmd --web="$web" \
    "${HD_BIND}:${HD_NOVNC_PORT}" \
    "127.0.0.1:${HD_VNC_PORT}"

  hd_wait_until 5 "noVNC" hd_is_alive novnc \
    || { tail -n 30 "$(hd_logfile novnc)" >&2; hd_die "noVNC/websockify failed"; }
  hd_log info "noVNC $(hd_novnc_url) (pid $(hd_read_pid novnc))"
}

hd_print_urls() {
  local url
  url="$(hd_novnc_url)"
  cat <<EOF
Display   : :${HD_DISPLAY}
VNC       : ${HD_BIND}:${HD_VNC_PORT}
noVNC     : ${url}
SSH tunnel:
  ssh -N -L ${HD_NOVNC_PORT}:127.0.0.1:${HD_NOVNC_PORT} -L ${HD_VNC_PORT}:127.0.0.1:${HD_VNC_PORT} user@host
Then open (drag-friendly params already in the URL):
  http://127.0.0.1:${HD_NOVNC_PORT}/vnc.html?$(hd_novnc_query)

Multi-session tiling (video-style):
  1. Right-click "New session" → Open in split → Right
  2. Or: Ctrl+T for a new tab; Ctrl+click a session to open as tab
  3. Drag a session to the chat edge to split (needs resize=remote URL above)
  CLI without drag:  hermes-desktop-headless split right
EOF
}

# Restart only the VNC layer (apply pointer-fidelity flags without bouncing Desktop).
hd_restart_vnc() {
  hd_mkdirs
  hd_kill_pidfile novnc
  hd_kill_pidfile x11vnc
  sleep 0.3
  hd_start_vnc
  hd_start_novnc
  hd_print_urls
}

# ---------------------------------------------------------------------------
# Split / tile helpers (no drag required — for noVNC and automation)
# ---------------------------------------------------------------------------
hd_hermes_window() {
  export DISPLAY=":${HD_DISPLAY}"
  hd_have xdotool || return 1
  local w
  w="$(xdotool search --onlyvisible --name 'Hermes' 2>/dev/null | head -1 || true)"
  if [[ -z "$w" ]]; then
    w="$(xdotool search --class Hermes 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$w" ]] && printf '%s\n' "$w"
}

# Drive "New session → Open in split → <dir>" via xdotool.
# dir: right|left|up|down (default right). Requires xdotool.
hd_split() {
  local dir="${1:-right}"
  export DISPLAY=":${HD_DISPLAY}"
  hd_have xdotool || hd_die "xdotool required for 'split' (sudo apt-get install -y xdotool)"
  hd_electron_on_display || pgrep -f 'linux-unpacked/Hermes' >/dev/null \
    || hd_die "Hermes Desktop is not running — start first"

  local wid
  wid="$(hd_hermes_window)" || hd_die "could not find Hermes window on :${HD_DISPLAY}"
  xdotool windowactivate --sync "$wid"
  sleep 0.25
  xdotool key --window "$wid" Escape Escape
  sleep 0.2

  # Geometry relative clicks: "New session" is top-left of the content chrome.
  local x y w h
  eval "$(xdotool getwindowgeometry --shell "$wid")"
  x=$X; y=$Y; w=$WIDTH; h=$HEIGHT

  # New session row (~ left rail, first item under titlebar)
  local nx ny
  nx=$((x + 90))
  ny=$((y + 70))
  xdotool mousemove --sync "$nx" "$ny"
  sleep 0.15
  xdotool click 3
  sleep 0.55

  # "Open in split" sits just below New session in the context menu
  xdotool mousemove --sync $((nx + 40)) $((ny + 20))
  sleep 0.35

  # Submenu directions: Right first (default), then Down, Left, Up
  local sx sy
  case "$dir" in
    right|r)  sx=$((nx + 130)); sy=$((ny + 28)) ;;
    down|d|bottom) sx=$((nx + 130)); sy=$((ny + 48)) ;;
    left|l)   sx=$((nx + 130)); sy=$((ny + 68)) ;;
    up|u|top) sx=$((nx + 130)); sy=$((ny + 88)) ;;
    *) hd_die "split dir must be right|left|up|down (got: $dir)" ;;
  esac

  # Open submenu by hovering Open in split, then click direction
  xdotool mousemove --sync $((nx + 50)) $((ny + 22))
  sleep 0.45
  xdotool mousemove --sync "$sx" "$sy"
  sleep 0.25
  xdotool click 1
  sleep 0.8

  hd_log info "split requested: $dir (window $wid)"
  echo "split $dir — if the layout did not change, use right-click New session → Open in split in the UI"
}

# Ctrl+T new session tab (stacked, not split).
hd_new_tab() {
  export DISPLAY=":${HD_DISPLAY}"
  hd_have xdotool || hd_die "xdotool required"
  local wid
  wid="$(hd_hermes_window)" || hd_die "Hermes window not found"
  xdotool windowactivate --sync "$wid"
  sleep 0.2
  xdotool key --window "$wid" ctrl+t
  hd_log info "sent Ctrl+T (new session tab)"
}

# ---------------------------------------------------------------------------
# Public commands
# ---------------------------------------------------------------------------
hd_start() {
  local foreground=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --foreground) foreground=1; shift ;;
      --no-vnc) HD_SKIP_VNC=1; shift ;;
      --bind) HD_BIND="$2"; shift 2 ;;
      --display) HD_DISPLAY="$2"; shift 2 ;;
      *) hd_die "unknown start flag: $1" ;;
    esac
  done

  hd_mkdirs
  if ! hd_doctor >/dev/null; then
    hd_log error "doctor failed - missing dependencies"
    hd_doctor --install-hints || true
    return 1
  fi

  hd_start_xvfb
  hd_start_dbus_wm
  hd_start_hermes
  hd_start_vnc
  hd_start_novnc
  hd_print_urls
  date -u +"%Y-%m-%dT%H:%M:%SZ started" >>"$HD_STATE_DIR/logs/lifecycle.log"

  if [[ "$foreground" -eq 1 ]]; then
    hd_log info "foreground mode - Ctrl-C stops the stack"
    trap 'hd_stop' INT TERM
    while hd_is_alive xvfb; do sleep 2; done
  fi
}

hd_stop() {
  hd_mkdirs
  hd_kill_pidfile hermes-desktop
  hd_kill_electron_on_display
  hd_kill_pidfile novnc
  hd_kill_pidfile x11vnc
  hd_kill_pidfile wm
  # legacy name from v0.1
  hd_kill_pidfile fluxbox
  hd_kill_pidfile dbus
  hd_kill_pidfile xvfb
  pkill -f "Xvfb :${HD_DISPLAY}" 2>/dev/null || true
  rm -f "/tmp/.X${HD_DISPLAY}-lock" 2>/dev/null || true
  hd_clear_singleton || true
  date -u +"%Y-%m-%dT%H:%M:%SZ stopped" >>"$HD_STATE_DIR/logs/lifecycle.log"
  hd_log info "stopped"
  echo "stopped"
}

hd_status() {
  hd_mkdirs
  local n
  for n in xvfb dbus wm hermes-desktop x11vnc novnc; do
    if hd_is_alive "$n"; then
      echo "UP   $n pid=$(hd_read_pid "$n")"
    else
      # compat: old fluxbox pidfile
      if [[ "$n" == wm ]] && hd_is_alive fluxbox; then
        echo "UP   wm(fluxbox) pid=$(hd_read_pid fluxbox)"
      else
        echo "DOWN $n"
      fi
    fi
  done
  if hd_electron_on_display; then
    echo "UP   electron DISPLAY=:${HD_DISPLAY}"
    pgrep -af 'linux-unpacked/Hermes' | head -3 || true
  else
    echo "DOWN electron"
  fi
  if [[ -e "/tmp/.X11-unix/X${HD_DISPLAY}" ]]; then
    echo "X socket :$HD_DISPLAY present"
  else
    echo "X socket :$HD_DISPLAY missing"
  fi
  hd_print_urls
}

hd_screenshot() {
  hd_load_runtime_env
  hd_export_display
  local tool out
  tool="$(hd_resolve_screenshot)" || hd_die "need scrot or ImageMagick import"
  out="${1:-$HD_STATE_DIR/logs/screenshot-$(date -u +%Y%m%dT%H%M%SZ).png}"
  mkdir -p "$(dirname "$out")"
  case "$tool" in
    scrot) scrot -o "$out" ;;
    import) import -window root "$out" ;;
    gnome-screenshot) gnome-screenshot -f "$out" ;;
  esac
  echo "$out"
}
