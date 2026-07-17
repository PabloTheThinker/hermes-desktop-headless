# Multi-session tiling (video-style)

Hermes Desktop can show **multiple chats at once** — tabs and/or a grid of
panes — the same feature demos on X/Twitter.

## Why drag felt broken

Session drag is a **pointer drag** (not HTML5 DnD). Two product issues made it
feel dead:

1. **Dropping on the chat body used to mean “insert `@session` chip”** (link),
   not “open a second pane”. Unless you hit a thin **edge band** or the **tab
   strip**, nothing visible happened (or an @chip appeared). That is what most
   people did after watching the video.
2. **noVNC** made edge targeting worse (scaled coords, laggy frames).

## Fixes (Hermes Desktop source + this headless helper)

### A. Desktop behavior (hermes-agent, rebuild Desktop)

| Drop target | Result (after fix) |
|-------------|--------------------|
| Chat **body** | Open session as **right split** (video default) |
| Chat **edge** | Split on that edge |
| **Tab strip** | Stack as a tab |
| **Composer** only | `@session` link chip |

Also: every session row menu has **Open in split → Right/Left/Up/Down**
(same as New session), not only “Open in new tab”.

### B. Headless / noVNC (this repo, v0.3+)

- Pointer-fidelity x11vnc (`-always_inject`, low defer/wait, `pointer_mode 1`)
- noVNC URL must use **`resize=remote`** (1:1 mouse coords)
- CLI when drag still fails: `hermes-desktop-headless split right`

```bash
hermes-desktop-headless restart-vnc
# open:
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote&quality=9&compression=0&show_dot=1
```

## Laptop (native Desktop, no headless repo)

After rebuilding/updating Hermes Desktop with the source fix above:

1. **Right-click any session** (not the active one) → **Open in split → Right**
2. Or **drag** that session onto the chat area (body or edge)
3. **Right-click New session → Open in split → Right** for a fresh chat beside
4. **Ctrl+T** / **Ctrl+click** session → tab (not split)

You cannot tile the *currently selected* session onto itself (by design: one
runtime). Switch to another session first, then split the previous one.

## Verify

```bash
# headless host
hermes-desktop-headless status
hermes-desktop-headless split right

# or in UI
# right-click session → Open in split → Right
```

## See also

- [README.md](../README.md)
- Upstream: `apps/desktop/src/app/chat/session-drag.ts`, `session-actions-menu.tsx`
