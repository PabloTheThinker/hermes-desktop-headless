# Contributing

Thanks for improving **hermes-desktop-headless**.

## Dev loop

```bash
make check    # bash -n + shellcheck (if installed)
make smoke    # offline unit checks (Hermes CLI optional)
make doctor   # full dependency report
```

## Guidelines

- Keep the CLI **bash-only** (no Python runtime required for the launcher).
- Prefer **portability**: new deps should resolve on Debian, Fedora, and Arch or document a fallback.
- Security defaults stay **loopback-only** unless a VNC password file is set.
- Do not commit secrets, hostnames, Tailscale IPs, or personal paths in screenshots/docs.
- Match existing style: small functions (`hd_*`), `set -euo pipefail`, no unnecessary abstraction.

## PR checklist

- [ ] `make check` passes  
- [ ] `make smoke` passes  
- [ ] README updated if UX/env vars change  
- [ ] No sensitive data in commits  

## Upstream Hermes

Session-token mint clobber is an upstream Hermes issue. The patch under `patches/` is optional; link issues rather than vendoring Hermes itself.
