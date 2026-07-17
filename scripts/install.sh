#!/usr/bin/env bash
# Cross-distro install: CLI + durable local patches + hermes-update wrapper.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

say() { printf '==> %s\n' "$*"; }

install_packages() {
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && . /etc/os-release
  local id="${ID:-unknown}"
  say "os=$id"
  case "$id" in
    ubuntu|debian|linuxmint|pop|raspbian)
      sudo apt-get update -qq
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xvfb x11vnc novnc websockify fluxbox scrot dbus-x11 xdotool
      ;;
    fedora|rhel|centos|rocky|almalinux)
      sudo dnf install -y \
        xorg-x11-server-Xvfb x11vnc novnc python3-websockify fluxbox scrot dbus-x11 xdotool || \
      sudo dnf install -y xorg-x11-server-Xvfb x11vnc python3-websockify fluxbox ImageMagick dbus-x11 xdotool
      ;;
    arch|manjaro|endeavouros)
      sudo pacman -S --needed --noconfirm \
        xorg-server-xvfb x11vnc novnc python-websockify fluxbox scrot dbus xdotool
      ;;
    opensuse*|sles)
      sudo zypper --non-interactive install \
        xorg-x11-server-Xvfb x11vnc novnc python3-websockify fluxbox scrot dbus-1-x11 xdotool
      ;;
    *)
      say "unknown distro - install manually: Xvfb x11vnc noVNC websockify fluxbox scrot dbus-x11 xdotool"
      ;;
  esac
}

install_durable_patches() {
  local dest="${HERMES_HOME:-$HOME/.hermes}/local-patches"
  local share="$HOME/.local/share/hermes-desktop-headless"
  mkdir -p "$dest" "$share/scripts" "$share/patches"
  cp -f "$ROOT/patches"/0001-*.patch \
        "$ROOT/patches"/0002-*.patch \
        "$ROOT/patches"/0003-*.patch \
        "$dest/"
  cp -f "$ROOT/patches"/0001-*.patch \
        "$ROOT/patches"/0002-*.patch \
        "$ROOT/patches"/0003-*.patch \
        "$share/patches/"
  cp -f "$ROOT/scripts/apply-desktop-patches.sh" "$share/scripts/"
  chmod +x "$share/scripts/apply-desktop-patches.sh"
  say "durable patches -> $dest (survive hermes-agent git reset)"
}

link_cli() {
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$ROOT/bin/hermes-desktop-headless" "$HOME/.local/bin/hermes-desktop-headless"
  ln -sfn "$ROOT/bin/hermes-desktop-headless-stop" "$HOME/.local/bin/hermes-desktop-headless-stop"
  ln -sfn "$ROOT/bin/hermes-update" "$HOME/.local/bin/hermes-update"
  ln -sfn "$ROOT/scripts/apply-desktop-patches.sh" "$HOME/.local/bin/hermes-apply-desktop-patches"
  ln -sfn "$ROOT/scripts/verify-everyday.sh" "$HOME/.local/bin/hermes-desktop-verify-everyday"
  say "linked: hermes-desktop-headless, hermes-update, hermes-apply-desktop-patches"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

main() {
  local with_pkgs=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --packages) with_pkgs=1; shift ;;
      -h|--help)
        echo "Usage: $0 [--packages]"
        echo "  --packages  also install OS packages (needs sudo)"
        echo "Installs headless CLI + hermes-update (re-applies patches after hermes update)."
        exit 0
        ;;
      *) echo "unknown: $1" >&2; exit 1 ;;
    esac
  done
  [[ "$with_pkgs" -eq 1 ]] && install_packages
  install_durable_patches
  link_cli
  "$HOME/.local/bin/hermes-desktop-headless" doctor --install-hints || true
  say "done."
  say "  headless:  hermes-desktop-headless start"
  say "  updates:   hermes-update          # NOT bare 'hermes update'"
  say "  patches:   hermes-apply-desktop-patches --force-build"
}

main "$@"
