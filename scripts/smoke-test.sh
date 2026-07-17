#!/usr/bin/env bash
# Offline unit checks (no root). Hermes CLI optional unless HD_SMOKE_REQUIRE_HERMES=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fail=1; }

[[ -f "$ROOT/VERSION" ]] && pass "VERSION exists" || bad "VERSION missing"
[[ -x "$ROOT/bin/hermes-desktop-headless" ]] && pass "cli executable" || bad "cli not executable"

if hd_resolve_novnc_web >/dev/null 2>&1; then
  pass "novnc web: $(hd_resolve_novnc_web)"
else
  bad "novnc web not found (install novnc)"
fi

if hd_resolve_websockify >/dev/null 2>&1; then
  pass "websockify: $(hd_resolve_websockify)"
else
  bad "websockify missing"
fi

if hd_resolve_wm >/dev/null 2>&1; then
  pass "wm: $(hd_resolve_wm)"
else
  bad "no window manager (fluxbox|openbox|icewm)"
fi

HD_BIND=127.0.0.1
hd_is_loopback_bind && pass "loopback 127.0.0.1" || bad "loopback detect"
HD_BIND=0.0.0.0
hd_is_loopback_bind && bad "0.0.0.0 should not be loopback" || pass "non-loopback 0.0.0.0"

# package hints always available
hints="$(hd_package_hints)"
[[ -n "$hints" ]] && pass "package hints" || bad "empty package hints"

# doctor: full clean only when hermes present; CI can run without hermes
if hd_have hermes; then
  if hd_doctor >/dev/null 2>&1; then
    pass "doctor clean"
  else
    bad "doctor reported missing deps"
  fi
elif [[ "${HD_SMOKE_REQUIRE_HERMES:-0}" == "1" ]]; then
  bad "hermes CLI required (HD_SMOKE_REQUIRE_HERMES=1)"
else
  pass "doctor skipped (hermes not on PATH — OK for shell-only CI)"
fi

# set -e regression: empty DBUS must not abort env export
HD_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hd-smoke-XXXXXX")"
mkdir -p "$HD_STATE_DIR/run"
unset DBUS_SESSION_BUS_ADDRESS || true
if hd_export_display && [[ -f "$HD_STATE_DIR/run/env.sh" ]]; then
  pass "export_display empty_dbus"
else
  bad "export_display empty_dbus"
fi
rm -rf "$HD_STATE_DIR"

exit "$fail"
