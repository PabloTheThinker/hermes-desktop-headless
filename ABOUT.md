# About

**hermes-desktop-headless** runs the real Hermes Desktop (Electron) on Linux servers that have no monitor, seat, or `$DISPLAY`.

## Problem

`hermes desktop` requires a graphical session. Headless VPS/cloud hosts exit with:

```text
Missing X server or $DISPLAY
```

That blocks multisession tabs, flexible layout, and Desktop plugins — even when CLI/Telegram agents work.

## Approach

A well-known self-hosted pattern:

1. **Xvfb** — virtual X server  
2. **Lightweight WM** — fluxbox/openbox/icewm (Electron expects a WM)  
3. **dbus session** — quieter desktop integrations  
4. **Hermes Desktop** — official `hermes desktop` binary  
5. **x11vnc + websockify/noVNC** — browser remote desktop over SSH tunnel  

Same family of stack used for headless Chrome/CI desktops and “desktop in a tab” self-hosting.

## Design goals

- Works on **common Linux distros** with package hints  
- **Secure by default** (loopback bind)  
- **One binary entrypoint**, small bash, no heavy runtime  
- Does **not** fork Hermes; only orchestrates the environment  

## Non-goals

- Multi-tenant SaaS browser isolation  
- Replacing `hermes dashboard` (SPA) when that is enough  
- Shipping a full desktop DE (XFCE/GNOME) — too heavy for agent boxes  

## Maintainers

Pablo Navarro / Vektra — GitHub issues and PRs welcome.
