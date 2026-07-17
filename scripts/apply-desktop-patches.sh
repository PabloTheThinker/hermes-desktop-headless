#!/usr/bin/env bash
# Apply Desktop UX + token patches to a hermes-agent checkout, then optionally rebuild Desktop.
# Safe for everyday users after `hermes update` resets local history.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Durable store (survives hermes-agent git reset) preferred when present.
if [[ -n "${HERMES_LOCAL_PATCHES:-}" && -d "${HERMES_LOCAL_PATCHES}" ]]; then
  PATCH_DIR="$HERMES_LOCAL_PATCHES"
elif [[ -d "${HOME}/.hermes/local-patches" ]] && ls "${HOME}/.hermes/local-patches"/0001-*.patch >/dev/null 2>&1; then
  PATCH_DIR="${HOME}/.hermes/local-patches"
else
  PATCH_DIR="$ROOT/patches"
fi
FORCE_BUILD=0
DRY=0
HERMES_ROOT="${HERMES_ROOT:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--hermes-root PATH] [--force-build] [--dry-run]

Applies:
  0001  preserve HERMES_DASHBOARD_SESSION_TOKEN under HERMES_DESKTOP=1
  0002  session drag: chat body → right split (not @session chip)
  0003  session menu: Open in split → Right/Left/Up/Down

Defaults HERMES_ROOT to:
  \$HERMES_ROOT, or dirname of \`hermes\` resolved under a git repo,
  or ~/.hermes/hermes-agent, or \$PWD if it looks like hermes-agent.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-root) HERMES_ROOT="$2"; shift 2 ;;
    --force-build) FORCE_BUILD=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown: $1" >&2; usage >&2; exit 1 ;;
  esac
done

resolve_hermes_root() {
  if [[ -n "$HERMES_ROOT" ]]; then
    printf '%s\n' "$HERMES_ROOT"
    return
  fi
  if command -v hermes >/dev/null 2>&1; then
    # Prefer install directory from hermes --version if present
    local line
    line="$(hermes --version 2>/dev/null | sed -n 's/^Install directory: //p' | head -1 || true)"
    if [[ -n "$line" && -d "$line" ]]; then
      printf '%s\n' "$line"
      return
    fi
  fi
  if [[ -d "${HOME}/.hermes/hermes-agent/apps/desktop" ]]; then
    printf '%s\n' "${HOME}/.hermes/hermes-agent"
    return
  fi
  if [[ -d "$PWD/apps/desktop" && -f "$PWD/hermes_cli/env_loader.py" ]]; then
    printf '%s\n' "$PWD"
    return
  fi
  return 1
}

HERMES_ROOT="$(resolve_hermes_root)" || {
  echo "Could not find hermes-agent checkout. Pass --hermes-root /path/to/hermes-agent" >&2
  exit 1
}

echo "hermes-root: $HERMES_ROOT"
cd "$HERMES_ROOT"

if [[ ! -f apps/desktop/src/app/chat/session-drag.ts ]]; then
  echo "Not a hermes-agent tree (missing apps/desktop/...)" >&2
  exit 1
fi

fail=0
for p in \
  "$PATCH_DIR/0001-preserve-desktop-session-token.patch" \
  "$PATCH_DIR/0002-session-drag-body-split.patch" \
  "$PATCH_DIR/0003-session-open-in-split-menu.patch"
do
  name="$(basename "$p")"
  if [[ ! -f "$p" ]]; then
    echo "MISSING $name" >&2
    fail=1
    continue
  fi
  if git apply --check "$p" 2>/dev/null; then
    if [[ "$DRY" -eq 1 ]]; then
      echo "OK   would apply $name"
    else
      git apply "$p"
      echo "OK   applied $name"
    fi
  else
    # Already applied?
    if git apply --reverse --check "$p" 2>/dev/null; then
      echo "SKIP $name (already applied)"
    else
      echo "FAIL $name (does not apply — re-port manually against this commit)" >&2
      fail=1
    fi
  fi
done

echo "--- verify markers ---"
if command -v rg >/dev/null 2>&1; then
  rg -n "desktop_preserve" hermes_cli/env_loader.py | head -3 || echo "WARN env_loader marker missing"
  rg -n "overComposer|Default body drop" apps/desktop/src/app/chat/session-drag.ts | head -3 || echo "WARN session-drag marker missing"
  rg -n "SplitSubmenu" apps/desktop/src/app/chat/sidebar/session-actions-menu.tsx | head -3 || echo "WARN session-actions-menu marker missing"
else
  grep -n "desktop_preserve\|overComposer\|SplitSubmenu" \
    hermes_cli/env_loader.py \
    apps/desktop/src/app/chat/session-drag.ts \
    apps/desktop/src/app/chat/sidebar/session-actions-menu.tsx 2>/dev/null | head -10 || true
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Some patches failed. See docs/MULTISESSION.md" >&2
  exit 1
fi

if [[ "$FORCE_BUILD" -eq 1 && "$DRY" -eq 0 ]]; then
  if command -v hermes >/dev/null 2>&1; then
    echo "→ hermes desktop --force-build"
    hermes desktop --force-build
  else
    echo "hermes CLI not on PATH; rebuild manually: cd apps/desktop && npm run pack" >&2
    exit 1
  fi
else
  echo "Next: hermes desktop --force-build   # or re-run with --force-build"
fi

echo "done"
