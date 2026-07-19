# MobileServerSwitch

A KDE Plasma widget + CLI collection for laptops that temporarily run as a
**mobile server** (remote-desktop / compute host) and get switched back to
normal laptop use afterwards. What started as a simple server/laptop toggle
has grown into a **comprehensive control and status center**: mode,
performance/power, remote access, services and firewall — all visible at a
glance and controllable remotely (over your Tailnet).

## Architecture

The plasmoid is **pure GUI**. All logic lives in small CLIs (*single source of
truth*); the widget only reads `msw-status --json` and calls the matching CLI
for actions. This guarantees the widget, the SSH CLI and any boot units always
agree.

**Privilege model:** reading is unprivileged. Write actions (sysfs, rfkill,
ethtool, firewalld) go exclusively through dedicated helpers under
`/usr/local/sbin` (`*-apply`), each of which enforces a **fixed whitelist** —
never a blanket `sudo` from the widget. One exception: the **Services tab**
starts/stops selected services directly via `sudo -n systemctl start|stop
<unit>`, where `<unit>` comes from a table hardcoded in QML (never free
input). Recommended sudoers entry, narrowly scoped (adjust the unit name(s)
to what you actually run):
`<user> ALL=(root) NOPASSWD: /usr/bin/systemctl start <unit>.service, /usr/bin/systemctl stop <unit>.service`
(if the entry is missing, `sudo -n` simply fails -> the switch does nothing, safely).

```
plasmoid/io.github.sunsetterphoto.mobileserverswitch/   Plasma applet (QML) — pure GUI, 6 tabs
bin/msw-mode                  server/laptop switch (PowerDevil, locker, services, charging)
bin/msw-status                state aggregator -> JSON (the widget interface)
bin/msw-perf                  performance: 3 presets (D-Bus PowerProfiles) + fine CPU cap
bin/msw-power                 power switches: dGPU / WiFi / Bluetooth / EPP / WoL
bin/msw-firewall               LAN blocks per app (firewalld, single zone)
bin/msw-krdp-setup             generates the KRDP live override from a template (password stays local)
system/usr-local-sbin/        privileged helpers: msw-charge-apply / -perf-apply /
                              -power-apply / -firewall-apply (fixed whitelists)
system/systemd/               msw-charge-thresholds.service (charge thresholds at boot)
system/systemd-user/          KRDP override template (Tailnet bind; no password in the repo)
docs/KRDP.md                  verified RDP setup
tests/                        shell test suites (sync, status JSON, perf/power/firewall)
scripts/sync.sh               syncs repo -> system (copy-only, idempotent, --dry-run)
```

### Install locations on the system

| Repo path | Target |
|---|---|
| `plasmoid/io.github.sunsetterphoto.mobileserverswitch/` | `~/.local/share/plasma/plasmoids/io.github.sunsetterphoto.mobileserverswitch/` |
| `bin/*` | `~/.local/bin/` |
| `system/usr-local-sbin/*` | `/usr/local/sbin/` (root) |
| `system/systemd/*.service` | `/etc/systemd/system/` (root) |

`scripts/sync.sh` syncs repo -> system (copy only, nothing destructive;
`--dry-run` shows what would happen beforehand). Reload the plasmoid:
`kquitapp6 plasmashell && kstart plasmashell`.

## The widget — 6 tabs

The default tab on open is **Overview**. Order:
`Overview | Performance | Mode | Remote Access | Services | Firewall`.

- **Overview** — compact, read-only summary (mode, performance, dGPU power
  draw, battery/AC, Tailnet IP, SSH/Sunshine status, active services, WoL).
  Sections are clickable and jump to the corresponding detail tab.
- **Performance** — 3 presets (power saver / balanced / performance) via
  KDE's PowerProfiles (`org.freedesktop.UPower.PowerProfiles`, tuned-ppd
  backend) + a fine **CPU-cap slider** (`intel_pstate/max_perf_pct`, 16–100 %,
  `no_turbo`). A preset only lights up when both the profile **and** the cap
  match. Plus devices/power: **dGPU** runtime PM (watts/awake/asleep + keep
  awake / allow sleep), **WiFi**, **Bluetooth** (rfkill), **EPP** energy bias.
- **Mode** — Server ⇄ Laptop. Switching to laptop stops Sunshine and the
  server services and therefore requires confirmation.
- **Remote Access** — status + details for SSH, Sunshine, KDE Connect, RDP
  (KRDP), VNC, Tailnet (copyable IP), Wake-on-LAN. **On/off switches for RDP
  and Sunshine**; SSH/Tailscale are deliberately read-only (lockout
  protection). WoL switch with NetworkManager persistence.
- **Services** — configurable list of user/system services with status,
  port/reachability and start/stop.
- **Firewall** — firewalld status (zone, LAN interfaces, open high ports, SSH
  allowed 🔒) + targeted **LAN blocks** for RDP / VNC / Sunshine / a
  configurable extra app. Blocks only affect the LAN zone; Tailnet access
  (zoneless) always stays reachable.

## Security model

- **SSH and Tailscale/the Tailnet are never switched or touched by the
  firewall** — no button, no rule. The firewall helper works with a fixed app
  whitelist and a defense-in-depth guard that refuses any rule touching port
  22 (fail closed).
- **RDP (KRDP)** is bound **exclusively to the Tailnet**, never `0.0.0.0`,
  Wayland-native via `--plasma`. Details + reproduction:
  [`docs/KRDP.md`](docs/KRDP.md). Passwords never live in the repo (only a
  sanitized override template + a setup helper).
- Risky live actions (CPU cap, services, rfkill, firewall) are reversible and
  never change remote reachability.

## CLIs (quick reference)

```
msw-status --json                 full state as JSON (widget interface)
msw-mode server|laptop            switch operating mode
msw-perf power-saver|balanced|performance | pct <16..100>
msw-power gpu keep|auto | wifi on|off | bt on|off | epp <pref> | wol on|off
msw-firewall block|allow <rdp|vnc|sunshine|comfyui> | status
```

## Tests

Shell test suites under `tests/` (assertions via `tests/lib.sh`, JSON via
`jq`). Firewall tests transiently mutate the LAN zone and clean up after
themselves (never touching SSH/Tailnet). Run:
`for t in tests/test_*.sh; do bash "$t"; done`.

## License

MIT © sunsetterphoto
