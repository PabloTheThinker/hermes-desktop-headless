# Security policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.4.x   | Yes |
| < 0.4   | Best-effort |

## Reporting a vulnerability

Open a **private** GitHub security advisory on
[PabloTheThinker/hermes-desktop-headless](https://github.com/PabloTheThinker/hermes-desktop-headless)
or contact the maintainer via GitHub. Do **not** file a public issue with
exploit details for auth/bind mistakes.

## Hardening defaults

- Binds **127.0.0.1** only unless you override `HD_BIND`
- Non-loopback bind **requires** `HD_VNC_PASSWORD_FILE`
- Prefer SSH tunnel / mesh VPN over public exposure of noVNC
- VNC without a password on a public interface is **unsafe**

## What not to commit

- Secrets, API tokens, `.env`, VNC password files
- Hostnames, Tailscale/`100.64.*` addresses, personal home paths
- Unredacted Desktop screenshots (session titles, `cwd`, project paths)

Run before every push:

```bash
gitleaks detect --source . --no-git
git grep -nE '/home/|100\\.64\\.|parallax|SUDO_PASSWORD|BEGIN .*PRIVATE' -- .
```
