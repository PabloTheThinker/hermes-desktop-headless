# Multi-session tiling (video-style)

Hermes Desktop can show **multiple chats at once** — tabs and/or a grid of
panes — the same feature demos on X/Twitter.

This document covers **using that UI over noVNC** (headless servers), where
native drag-and-drop often fails.

## Why drag breaks in noVNC

Session splits in Hermes use a **pointer drag session** (not HTML5 DnD). Over
noVNC, three things commonly break it:

1. **Scaled display** (`resize=scale`) — mouse coordinates no longer match
   drop targets.
2. **High VNC defer/wait** — frame updates lag the pointer, so edge hit-tests
   miss.
3. **Missing zero-motion injects** — menu clicks / slow drags send `dx=dy=0`
   events that some VNC paths drop.

## What this project does about it

### 1. Pointer-fidelity x11vnc (default since v0.3)

```
-always_inject
-pointer_mode 1
-cursor most
-defer 1
-wait 5
-wait_ui 0.5
```

Re-apply without restarting Desktop:

```bash
hermes-desktop-headless restart-vnc
```

### 2. Drag-friendly noVNC URL

Always open:

```
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote&quality=9&compression=0&show_dot=1
```

| Param | Why |
|-------|-----|
| `resize=remote` | 1:1 coordinates (required for edge drops) |
| `quality=9` + `compression=0` | Less smear during drag |
| `show_dot=1` | Local cursor for hit-testing |

`hermes-desktop-headless url` prints this string.

### 3. No-drag CLI (works even if VNC drag is hopeless)

```bash
# Side-by-side chat (video look) — needs xdotool
sudo apt-get install -y xdotool   # once
hermes-desktop-headless split right
hermes-desktop-headless split down

# Stacked tab only
hermes-desktop-headless new-tab   # Ctrl+T
```

### 4. In-app gestures (Hermes itself)

| Goal | Action |
|------|--------|
| New tab | **Ctrl+T** |
| Open session as tab | **Ctrl+click** session row, or right-click → **Open in new tab** |
| New chat in split | Right-click **New session** → **Open in split** → Right/Left/Up/Down |
| Drag split | Drag session from list to **edge** of chat (needs drag-friendly URL) |

## Verify

```bash
hermes-desktop-headless status
hermes-desktop-headless url
# after restart-vnc, x11vnc log should mention pointer-fidelity
hermes-desktop-headless split right
hermes-desktop-headless screenshot /tmp/after-split.png
```

## See also

- [README.md](../README.md) — install / security
- Hermes upstream multisession: session tiles + pane-shell drag session
