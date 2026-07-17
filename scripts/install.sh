#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/.local/bin"
ln -sfn "$ROOT/bin/hermes-desktop-headless" "$HOME/.local/bin/hermes-desktop-headless"
ln -sfn "$ROOT/bin/hermes-desktop-headless-stop" "$HOME/.local/bin/hermes-desktop-headless-stop"
echo "installed: hermes-desktop-headless → $HOME/.local/bin/"
"$HOME/.local/bin/hermes-desktop-headless" doctor || true
