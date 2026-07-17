# About

**hermes-desktop-headless** is a small ops utility for people who run [Hermes Agent](https://hermes-agent.nousresearch.com/) on **servers without a monitor**.

## Problem

Hermes Desktop is Electron. Headless Linux has no `$DISPLAY`. The official `hermes desktop` command cannot show a window, so you lose:

- Multisession tabs  
- Flexible pane layout  
- Desktop plugins and chrome  

…even when `hermes serve` / gateway are healthy for CLI and Telegram.

## Solution

A single CLI starts a known-good stack:

1. **Xvfb** — virtual 1920×1080 display  
2. **dbus + fluxbox** — session bus + window manager (Electron behaves better)  
3. **Hermes Desktop** — real packaged app (`hermes desktop --skip-build`)  
4. **x11vnc + noVNC** — view/control from a browser via SSH tunnel  

Defaults are **localhost-only**. Reach the UI with SSH port-forward or a mesh VPN; do not expose raw VNC to the public internet without a password file.

## Origin

Built for a production Hermes install on a headless host where Desktop failed with `Missing X server or $DISPLAY`, then failed again with a boot-time **401** because `~/.hermes/.env` overwrote Desktop’s minted session token. Both issues are handled or documented here.

## Non-goals

- Not a fork of Hermes  
- Not a multi-tenant SaaS control plane  
- Not a replacement for `hermes dashboard` (browser SPA) when that fits your workflow  

## Maintainers

Vektra / Pablo Navarro — issues and PRs on the GitHub repo.
