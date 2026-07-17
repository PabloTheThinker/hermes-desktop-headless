#!/usr/bin/env bash
# Everyday health check for a running headless Desktop stack + optional backend.
# Exit 0 only if the stack is usable for day-to-day work.
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
CLI="${CLI:-hermes-desktop-headless}"
fail=0
ok()  { printf 'OK  %s\n' "$*"; }
bad() { printf 'BAD %s\n' "$*"; fail=$((fail + 1)); }

if ! command -v "$CLI" >/dev/null 2>&1; then
  bad "CLI not on PATH ($CLI)"
  exit 1
fi

ok "cli $($CLI version 2>/dev/null | tr -d '\n' || echo unknown)"

status="$($CLI status 2>/dev/null || true)"
if printf '%s\n' "$status" | grep -qE '^UP[[:space:]]+xvfb'; then ok xvfb; else bad xvfb; fi
if printf '%s\n' "$status" | grep -qE 'electron'; then ok electron_line; else bad electron_line; fi
if pgrep -f 'linux-unpacked/Hermes' >/dev/null 2>&1; then ok electron_proc; else bad electron_proc; fi
if [[ -S /tmp/.X11-unix/X${HD_DISPLAY:-99} ]]; then ok x11_socket; else bad x11_socket; fi

code="$(curl -sS -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HD_NOVNC_PORT:-6080}/vnc.html" 2>/dev/null || echo 000)"
if [[ "$code" == 200 ]]; then ok "novnc_http=$code"; else bad "novnc_http=$code"; fi

if pgrep -af 'x11vnc' 2>/dev/null | grep -q always_inject; then
  ok x11vnc_pointer_fidelity
else
  bad 'x11vnc_pointer_fidelity (run: hermes-desktop-headless restart-vnc)'
fi

# Desktop-spawned backend (optional but expected when Desktop is healthy)
if python3 - <<'PY'
import os, re, subprocess, urllib.request, sys
ss = subprocess.check_output(["ss", "-lntp"], text=True)
ports = []
for line in ss.splitlines():
    if "hermes" not in line:
        continue
    m = re.search(r"127\.0\.0\.1:(\d+)", line)
    if m:
        ports.append(int(m.group(1)))
found = False
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        env = open(f"/proc/{pid}/environ", "rb").read()
        cmd = open(f"/proc/{pid}/cmdline", "rb").read()
    except Exception:
        continue
    if b"HERMES_DESKTOP=1" not in env or b"serve" not in cmd:
        continue
    e = dict(x.split(b"=", 1) for x in env.split(b"\x00") if x and b"=" in x)
    tok = e.get(b"HERMES_DASHBOARD_SESSION_TOKEN", b"").decode()
    if not tok:
        continue
    for p in ports:
        if p == 9119:
            continue
        req = urllib.request.Request(
            f"http://127.0.0.1:{p}/api/config",
            headers={"X-Hermes-Session-Token": tok},
        )
        try:
            with urllib.request.urlopen(req, timeout=2) as r:
                if r.status == 200:
                    print(f"OK  desktop_backend port={p}")
                    found = True
        except Exception:
            pass
    break
if not found:
    print("BAD desktop_backend (no HERMES_DESKTOP serve with working token)")
    sys.exit(2)
PY
then
  :
else
  fail=$((fail + 1))
fi

echo "----"
echo "FAILS=$fail"
if [[ $fail -eq 0 ]]; then
  echo "EVERYDAY_OK"
  $CLI url 2>/dev/null | head -8 || true
  exit 0
fi
echo "EVERYDAY_FAIL — try: hermes-desktop-headless restart && hermes-desktop-headless restart-vnc"
exit 1
