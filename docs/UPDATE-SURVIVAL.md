# Surviving `hermes update`

## The problem

`hermes update` may:

1. **`git reset --hard origin/<branch>`** when history diverged → **wipes uncommitted
   local patches** inside the hermes-agent tree.
2. Report **Desktop app up to date** and **skip Electron rebuild** even when you
   needed a rebuild for UI fixes.

So Desktop drag/split and token-preserve fixes disappear until re-applied.

## Durable fix (this project)

Patches live **outside** the hermes-agent git tree:

```
~/.hermes/local-patches/0001-preserve-desktop-session-token.patch
~/.hermes/local-patches/0002-session-drag-body-split.patch
~/.hermes/local-patches/0003-session-open-in-split-menu.patch
```

### Always update with:

```bash
hermes-update
# not: hermes update
```

That runs official update, then re-applies patches from `~/.hermes/local-patches`
and **`hermes desktop --force-build`**.

### One-time install

```bash
cd hermes-desktop-headless
./scripts/install.sh
# installs:
#   ~/.local/bin/hermes-update
#   ~/.local/bin/hermes-apply-desktop-patches
#   ~/.hermes/local-patches/*
```

### Manual re-apply

```bash
hermes-apply-desktop-patches --force-build
```

## Long-term: upstream

Until Nous merges equivalent changes, re-apply is required after resets.
Track: patches/ + PR from fork (session drag body→split, Open in split menu,
env_loader desktop token preserve).

## Vector / multi-machine

Run `./scripts/install.sh` on **each** machine that runs Desktop (laptop + server).
Headless stack is optional; **patches + hermes-update** are the survival kit.
