# Contributing to Mobile AI Server Switch

Thanks for your interest in contributing. This project is a small,
security-conscious tool, so the bar for changes touching privileged code
paths is intentionally high. This document covers the essentials; if
something is unclear, open an issue first.

## Ground rules

- **English throughout.** All code, comments, commit messages, UI strings and
  docs are English. No i18n scaffolding in v1.
- **CLI is the single source of truth.** The plasmoid (QML) is pure GUI: it
  reads `msw-status --json` and calls the matching CLI for actions. It never
  re-implements logic that a CLI already owns. Any new capability starts in a
  CLI, with the widget as a thin consumer.
- **Safety invariants are non-negotiable.** No code path — CLI, privileged
  helper, or QML — may ever:
  - stop, restart or reconfigure `sshd`/`tailscaled`,
  - add a firewall rule that touches port 22/ssh or the Tailscale
    interface/zone,
  - bind a remote-access service (RDP) to anything other than the Tailnet.
  These are defense-in-depth, not just documentation: the firewall helper
  hard-refuses port-22 rules regardless of config, and the KRDP setup helper
  refuses to write a live override if no Tailnet address can be detected
  (fail closed).
- **Privilege separation stays intact.** Reads are unprivileged. Writes to
  system state (sysfs, rfkill, ethtool, firewalld) go exclusively through the
  dedicated `msw-*-apply` helpers under `system/usr-local-sbin/`, each
  enforcing a fixed whitelist. Never add a blanket `sudo` call from the
  widget or a CLI; extend a helper's whitelist instead, and keep the
  sudoers grant (`packaging/mobileserverswitch.sudoers`) scoped to exactly
  the helper paths.
- **No personal data.** No real hostnames, IPs, usernames, or paths under
  `/home/<user>` in code, comments, docs, or test fixtures. Auto-detection
  functions in `bin/msw-config` exist precisely so nothing has to be
  hardcoded.
- **Config is additive and optional.** `~/.config/mobileserverswitch/config.json`
  keys should default to `"auto"`/runtime detection when absent; a missing
  config file must never break a CLI.

## Developing

1. Clone the repo and make changes under `bin/`, `system/`, or
   `plasmoid/io.github.sunsetterphoto.mobileserverswitch/`.
2. Deploy your changes to a running system with the dev sync loop (this is
   the fast inner loop — copy-only, idempotent, safe to re-run):

   ```bash
   scripts/sync.sh            # copies repo -> system paths
   scripts/sync.sh --dry-run  # preview only, no changes
   ```

3. Reload the plasmoid to pick up QML changes:

   ```bash
   kquitapp6 plasmashell && kstart plasmashell
   ```

4. Lint QML before submitting (requires `qmllint-qt6` / `qmllint6`):

   ```bash
   find plasmoid -name '*.qml' -print0 | xargs -0 -n1 qmllint6
   ```

## Testing

All shell logic has a corresponding test suite under `tests/` (assertions
via `tests/lib.sh`, JSON handling via `jq`). Run the full suite:

```bash
for t in tests/test_*.sh; do bash "$t"; done
```

Notes:

- Firewall tests transiently mutate the LAN firewall zone and clean up after
  themselves; they never touch the SSH rule or the Tailscale
  interface/zone. Run them on a machine where a brief, self-reverting
  firewalld change is acceptable.
- `install.sh`/`uninstall.sh` tests run against a sandboxed `$HOME` and never
  touch your real system.
- When adding a new CLI flag or config key, add or extend a test in
  `tests/` alongside the implementation — this is a shell codebase without a
  static type system, so tests are the main safety net.

## Pull requests

- Keep PRs focused; one behavioral change per PR is easiest to review.
- Explain *why* in the description, not just *what* — especially for
  anything touching privileged helpers or the firewall/RDP paths.
- Run the full test suite and `qmllint6` locally before opening the PR.
- Re-run the personal-data grep before pushing if you touched docs, tests,
  or fixtures: search the tree for any real username, `/home/<user>` path,
  hostname, or IP address. Only generic placeholders (`<USERNAME>`,
  `<HOSTNAME>`, `<TAILNET_IP>`, `$(id -un)`) belong in committed files.
