# hermes-desktop-headless

**Run [Hermes Desktop](https://hermes-agent.nousresearch.com/) on a headless Linux server** — no physical monitor, no `$DISPLAY` from a seat. Opens the real Electron app under a virtual framebuffer and exposes it in the browser via noVNC.

| | |
|---|---|
| **Status** | Working on Ubuntu 24.04 / Hermes Agent ≥ 0.18 |
| **Stack** | Xvfb · dbus · fluxbox · Hermes Desktop · x11vnc · websockify/noVNC |
| **Default bind** | `127.0.0.1` only (SSH tunnel or Tailscale to reach it) |

![hero](docs/screenshots/public-hero.png)

## Why this exists

`hermes desktop` is an Electron app. On a bare metal/VPS box with no GUI session it dies immediately:

```text
Missing X server or $DISPLAY
The platform failed to initialize. Exiting.
```

This project gives you a one-command stack so you can still use **multisession tabs**, **flexible layout**, plugins, and the full Desktop chrome from a browser or VNC client.

## Screenshots

### Before (gateway 401 / boot failure)

When Desktop’s minted session token was overwritten by `~/.hermes/.env` (`load_dotenv(override=True)`), the UI showed:

![boot failure](docs/screenshots/public-boot-failure-before-fix.png)

### After (Desktop ready under Xvfb)

Sensitive panes blurred for the public README:

![desktop ready](docs/screenshots/public-desktop-ready.png)

## Quick start

### Dependencies (Debian/Ubuntu)

```bash
sudo apt-get install -y xvfb x11vnc novnc websockify fluxbox scrot dbus-x11
# Hermes Agent already installed and `hermes` on PATH
```

### Install

```bash
git clone https://github.com/PabloTheThinker/hermes-desktop-headless.git
cd hermes-desktop-headless
ln -sfn "$PWD/bin/hermes-desktop-headless" ~/.local/bin/hermes-desktop-headless
hermes-desktop-headless doctor
```

### Run

```bash
hermes-desktop-headless start
# → noVNC: http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
```

From your laptop:

```bash
ssh -N -L 6080:127.0.0.1:6080 user@your-server
# open http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
```

### Control

```bash
hermes-desktop-headless status
hermes-desktop-headless screenshot /tmp/hermes.png
hermes-desktop-headless stop
hermes-desktop-headless restart
```

### Optional user systemd unit

```bash
mkdir -p ~/.config/systemd/user
cp systemd/hermes-desktop-headless.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-desktop-headless.service
```

## Architecture

```text
 Browser / VNC client
         │
         ▼
   websockify :6080  (noVNC static + WS)
         │
         ▼
     x11vnc :5901
         │
         ▼
      Xvfb :99  ←── fluxbox (WM)
         │
         ▼
  Hermes Desktop (Electron)
         │ spawns
         ▼
  hermes serve --port 0   (per-profile pool backend)
```

## Security

| Default | Rationale |
|---------|-----------|
| Bind `127.0.0.1` | VNC/noVNC not on the public internet |
| No VNC password on localhost | Acceptable only for loopback; tunnel with SSH |
| Non-localhost bind **requires** `HD_VNC_PASSWORD_FILE` | Refuses open bind without auth |

```bash
# Example: password file for x11vnc (never commit this)
x11vnc -storepasswd /path/to/vnc.pass
export HD_VNC_PASSWORD_FILE=/path/to/vnc.pass
export HD_BIND=0.0.0.0   # still prefer Tailscale/SSH over open WAN
hermes-desktop-headless start
```

**Do not** put tokens, Tailscale IPs, or host absolute paths in public forks of this repo.

## Important: Desktop session-token fix

Hermes Desktop mints `HERMES_DASHBOARD_SESSION_TOKEN` for each spawned `hermes serve` child.  
`load_hermes_dotenv()` loads `~/.hermes/.env` with **`override=True`**, which can **clobber that mint**. Electron then 401s against its own backend and shows *“Could not connect to Hermes gateway”*.

This repo documents the failure. A small preserve-mint patch for `hermes_cli/env_loader.py` is included under [`patches/`](patches/) — apply on the machine that runs Desktop:

```bash
# from your hermes-agent checkout
patch -p1 < /path/to/hermes-desktop-headless/patches/0001-preserve-desktop-session-token.patch
```

(Or merge the equivalent logic upstream.)

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `HD_DISPLAY` | `99` | X display number |
| `HD_GEOMETRY` | `1920x1080x24` | Xvfb screen |
| `HD_VNC_PORT` | `5901` | RFB port |
| `HD_NOVNC_PORT` | `6080` | Browser UI |
| `HD_BIND` | `127.0.0.1` | Listen address |
| `HD_STATE_DIR` | `~/.local/state/hermes-desktop-headless` | PIDs + logs |
| `HD_HERMES_CMD` | `hermes desktop --skip-build` | Launch command |
| `HD_VNC_PASSWORD_FILE` | _(empty)_ | x11vnc `-rfbauth` file |

## Multisession / layout (what the X demos show)

Once Desktop is up in noVNC:

1. **⌘/Ctrl+K** → `New session tab`
2. **⌘/Ctrl+K** → `Toggle layout edit mode`
3. Drag session tabs into panes / edges

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No graphical display` from plain `hermes desktop` | Use **this** launcher, not bare CLI |
| Singleton lock / app won’t start | Launcher clears **dead** `~/.config/Hermes/Singleton*` |
| Boot overlay 401 / gateway | Apply session-token patch; restart stack |
| Black VNC | Wait for Electron; `hermes-desktop-headless screenshot` |
| Port in use | `HD_DISPLAY=98 HD_VNC_PORT=5902 HD_NOVNC_PORT=6081 start` |

Logs: `$HD_STATE_DIR/logs/` (`xvfb`, `hermes-desktop`, `x11vnc`, `novnc`).

## License

MIT — see [LICENSE](LICENSE).

Hermes Agent / Desktop remain under their upstream licenses (Nous Research).
