# hermes-desktop-headless

**Run [Hermes Desktop](https://hermes-agent.nousresearch.com/) on any headless Linux box** — VPS, bare metal, CI — without a physical monitor.

Virtual framebuffer + lightweight WM + VNC + browser client. Defaults to **localhost-only** access via SSH tunnel.

[![version](https://img.shields.io/badge/version-0.3.2-blue)](VERSION)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![ci](https://github.com/PabloTheThinker/hermes-desktop-headless/actions/workflows/ci.yml/badge.svg)](https://github.com/PabloTheThinker/hermes-desktop-headless/actions/workflows/ci.yml)

![hero](docs/screenshots/public-hero.png)

## Who is this for?

| You are… | Useful? | Use this |
|----------|---------|----------|
| Running Hermes on a **VPS / server with no monitor** | **Yes** | This repo end-to-end (`start` → noVNC) |
| On a **laptop with a screen** and native Hermes Desktop | **Partially** | Only the **patches** (`scripts/apply-desktop-patches.sh`) if drag/split is wrong or Desktop 401s after update — **not** the Xvfb stack |
| Only using Telegram / CLI / dashboard | **No** | You don’t need this |
| Want video-style multi-chat tiling | **Yes (patches)** | Upstream still drops on chat body as `@session` link; our Desktop patches fix that |

**Honest take:** The headless stack is a real product for agent servers. The Desktop patches are the piece most **interactive** users feel daily — until Nous merges equivalent UX, re-apply after `hermes update` resets.

## Features

- **One CLI**: `start` / `stop` / `status` / `screenshot` / `doctor` / `split` / `new-tab` / `restart-vnc`
- **Portable deps**: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE package hints
- **WM auto-pick**: fluxbox → openbox → icewm → matchbox
- **noVNC discovery**: `/usr/share/novnc`, Arch webapps path, overrides
- **websockify**: binary or `python3 -m websockify`
- **Pointer-fidelity VNC**: low-latency x11vnc + drag-friendly noVNC URL (session tiling)
- **No-drag split CLI**: `split right` via xdotool when browser drag fails
- **Post-update restore**: `scripts/apply-desktop-patches.sh` + force Desktop rebuild
- **Everyday check**: `scripts/verify-everyday.sh` (stack + backend token)
- **Safe process kill**: only Electron on *our* `DISPLAY`
- **Security default**: loopback bind; password required off-localhost

## Screenshots

### Boot failure (token clobber) → fixed stack

![boot failure](docs/screenshots/public-boot-failure-before-fix.png)

![desktop ready](docs/screenshots/public-desktop-ready.png)

## Quick start

```bash
git clone https://github.com/PabloTheThinker/hermes-desktop-headless.git
cd hermes-desktop-headless
./scripts/install.sh --packages    # sudo: OS packages + ~/.local/bin link
# or without packages:
./scripts/install.sh

hermes-desktop-headless doctor --install-hints
hermes-desktop-headless start
```

## Laptop users (no headless stack)

If Desktop already runs on a real display and you only need **tiling that matches the demos**:

```bash
git clone https://github.com/PabloTheThinker/hermes-desktop-headless.git
cd hermes-desktop-headless
./scripts/apply-desktop-patches.sh --force-build
# fully quit Hermes Desktop, reopen
```

Details: [docs/MULTISESSION.md](docs/MULTISESSION.md).

## Everyday health

```bash
./scripts/verify-everyday.sh
# or after start:
hermes-desktop-headless status
hermes-desktop-headless url
```

```bash
ssh -N -L 6080:127.0.0.1:6080 user@server
# browser:
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
```

## Architecture

```text
  Browser ──► websockify:6080 (noVNC) ──► x11vnc:5901 ──► Xvfb:99
                                                              │
                                              fluxbox/openbox + Hermes Desktop
                                                              │
                                                    hermes serve --port 0
```

Industry-standard headless GUI pattern (Xvfb + x11vnc + noVNC), specialized for Hermes Desktop.

## Commands

| Command | Purpose |
|---------|---------|
| `start [--foreground] [--no-vnc] [--bind ADDR] [--display N]` | Bring stack up |
| `stop` / `restart` | Tear down / bounce |
| `restart-vnc` | Re-apply pointer-fidelity VNC flags only |
| `status` / `url` | Health + drag-friendly access URLs |
| `screenshot [path.png]` | Capture virtual display |
| `split [right\|left\|up\|down]` | **Open in split** without drag (needs `xdotool`) |
| `new-tab` | Ctrl+T new session tab (needs `xdotool`) |
| `doctor [--install-hints]` | Dependency check + distro install line |
| `version` | Print package version |

## Environment

| Variable | Default | Notes |
|----------|---------|-------|
| `HD_DISPLAY` | `99` | X display number |
| `HD_GEOMETRY` | `1920x1080x24` | Xvfb screen |
| `HD_VNC_PORT` | `5901` | RFB |
| `HD_NOVNC_PORT` | `6080` | Browser |
| `HD_BIND` | `127.0.0.1` | Listen address |
| `HD_STATE_DIR` | `~/.local/state/hermes-desktop-headless` | PIDs + logs |
| `HD_HERMES_CMD` | `hermes desktop --skip-build` | Launch command |
| `HD_WM` | _(auto)_ | Prefer a specific WM |
| `HD_NOVNC_WEB` | _(auto)_ | noVNC static root |
| `HD_VNC_PASSWORD_FILE` | _(empty)_ | Required if not loopback |
| `HD_WAIT_HERMES_SEC` | `45` | Electron ready timeout |

## Security

1. **Loopback by default** — VNC/noVNC not on the public internet  
2. **Non-loopback refused** without `HD_VNC_PASSWORD_FILE` (`x11vnc -storepasswd`)  
3. Prefer **SSH tunnel** or **Tailscale** over opening ports  

```bash
x11vnc -storepasswd ~/.config/hermes-desktop-headless/vnc.pass
export HD_VNC_PASSWORD_FILE=~/.config/hermes-desktop-headless/vnc.pass
# still prefer not exposing 0.0.0.0 to the open WAN
```

## Hermes session-token bug

Desktop mints `HERMES_DASHBOARD_SESSION_TOKEN` for each spawned backend.  
`load_hermes_dotenv()` loads `~/.hermes/.env` with **`override=True`**, which can overwrite that mint → Electron **401** → *“Could not connect to Hermes gateway”*.

Upstream issue class: [NousResearch/hermes-agent#39349](https://github.com/NousResearch/hermes-agent/issues/39349)

**Workarounds:**
1. Apply [`patches/0001-preserve-desktop-session-token.patch`](patches/0001-preserve-desktop-session-token.patch) to your hermes-agent tree  
2. Or remove `HERMES_DASHBOARD_SESSION_TOKEN` from `~/.hermes/.env` and relaunch  

## Multisession / layout (X-demo class)

With Desktop up in noVNC (use the URL from `hermes-desktop-headless url`):

1. **Right-click New session → Open in split → Right** — side-by-side chats  
2. **Ctrl+T** or `hermes-desktop-headless new-tab` — new session tab  
3. **Ctrl+click** a session — open as tab  
4. Drag session to chat **edge** — split (requires `resize=remote` URL)  
5. **No drag?** `hermes-desktop-headless split right`

Full guide: **[docs/MULTISESSION.md](docs/MULTISESSION.md)**.

```bash
# apply pointer-fidelity flags if you started before v0.3
hermes-desktop-headless restart-vnc
hermes-desktop-headless split right
```

## systemd (user)

```bash
mkdir -p ~/.config/systemd/user
cp systemd/hermes-desktop-headless.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-desktop-headless.service
```

## Development

```bash
make check    # bash -n + shellcheck
make smoke    # offline unit tests (Hermes optional)
make doctor
./scripts/install.sh [--packages]
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Missing X server or $DISPLAY` | Use this tool, not bare `hermes desktop` |
| Doctor MISS packages | `./scripts/install.sh --packages` or `doctor --install-hints` |
| Boot overlay 401 | Session-token patch / remove token from `.env` |
| Singleton lock | `stop` clears dead locks; or delete `~/.config/Hermes/Singleton*` if PID dead |
| Port busy | `HD_DISPLAY=98 HD_VNC_PORT=5902 HD_NOVNC_PORT=6081 start` |

Logs: `$HD_STATE_DIR/logs/` (`xvfb`, `wm`, `hermes-desktop`, `x11vnc`, `novnc`).

## License

MIT — see [LICENSE](LICENSE).  
Hermes Agent / Desktop: Nous Research upstream licenses.

## About

See [ABOUT.md](ABOUT.md).
