#!/usr/bin/env bash
# Offline unit checks (no root, no X required for most).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fail=1; }

# syntax via bash -n done by caller; functional:
[[ -f "$ROOT/VERSION" ]] && pass "VERSION exists" || bad "VERSION missing"
[[ -x "$ROOT/bin/hermes-desktop-headless" ]] && pass "cli executable" || bad "cli not executable"

# resolver smoke
if hd_resolve_novnc_web >/dev/null 2>&1; then
  pass "novnc web: $(hd_resolve_novnc_web)"
else
  bad "novnc web not found (install novnc package for full stack)"
fi

if hd_resolve_websockify >/dev/null 2>&1; then
  pass "websockify: $(hd_resolve_websockify)"
else
  bad "websockify missing"
fi

if hd_resolve_wm >/dev/null 2>&1; then
  pass "wm: $(hd_resolve_wm)"
else
  bad "no window manager"
fi

# loopback guard logic
HD_BIND=127.0.0.1
hd_is_loopback_bind && pass "loopback 127.0.0.1" || bad "loopback detect"
HD_BIND=0.0.0.0
hd_is_loopback_bind && bad "0.0.0.0 should not be loopback" || pass "non-loopback 0.0.0.0"

# doctor returns 0 when deps present
if hd_doctor >/dev/null; then
  pass "doctor clean"
else
  bad "doctor reported missing deps"
fi

# package hints non-empty
hints="$(hd_package_hints)"
[[ -n "$hints" ]] && pass "package hints" || bad "empty package hints"

exit "$fail"
