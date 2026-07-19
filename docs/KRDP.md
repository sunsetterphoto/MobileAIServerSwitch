# KRDP — Wayland-native RDP, reachable only over the Tailnet

Optional Wayland-native remote desktop via [KRDP](https://invent.kde.org/plasma/krdp),
KDE's own RDP server. Setup below is verified against Plasma 6.7 on Wayland;
package/unit names may differ slightly on other distros or Plasma point
releases.

## What & why

- **Package:** `krdp` (Fedora: `krdp-6.7.x`, package names vary by distro) →
  binary `/usr/bin/krdpserver`, user unit
  `app-org.kde.krdpserver.service`, KCM `kcm_krdpserver` (System Settings →
  "Remote Desktop").
- **Goal:** RDP access to the running desktop, **exclusively over the
  Tailnet** (`<TAILNET_IP>:3389`), never on `0.0.0.0`.

## Why a systemd user override (instead of the KCM)

`krdpserver --help` shows that the bind address is only settable via
`--address` (default `0.0.0.0`). The KCM stores username/password securely in
KWallet but offers **no** address setting. To get the Tailnet-only bind we
need explicit flags — hence a drop-in override on the stock unit:

```
~/.config/systemd/user/app-org.kde.krdpserver.service.d/override.conf   (mode 600)
```

The override only replaces `ExecStart`; the stock unit's ordering/environment
(`After=plasma-*`, `WantedBy=plasma-workspace.target`) is preserved, so the
service still runs inside the graphical session with a valid
`WAYLAND_DISPLAY`/KWin access.

Effective invocation (values shown as placeholders — see below for how they
are filled in):

```
/usr/bin/krdpserver --plasma \
  --address <TAILNET_IP> --port 3389 \
  --certificate  %h/.local/share/krdpserver/server.crt \
  --certificate-key %h/.local/share/krdpserver/server.key \
  --username <USERNAME> --password <secret>
```

- `--plasma`: KWin-native screencast + fake input instead of the XDG
  RemoteDesktop portal → **no** consent dialog on connect (unattended server
  operation).
- **TLS certificate:** generated once via the KCM, `CN=<HOSTNAME>` (your
  machine's `hostname`), stored under
  `~/.local/share/krdpserver/server.{crt,key}`. Self-signed → accept it once
  in the RDP client.

## Security: the password never lives in the repo

`krdpserver` only accepts the password via `-p/--password` (no
`--password-file`, no environment variable). It therefore ends up in the live
override file (mode 600) and is visible in the process command line (`ps`)
to the **owning** user. Acceptable on a single-user machine, but the file is
**never** committed.

The repo only contains the **template** with placeholders:
`system/systemd-user/app-org.kde.krdpserver.service.d/override.conf.template`.
The template uses two placeholders, `__TAILNET_IP__` and `__RDP_PASSWORD__`;
`bin/msw-krdp-setup` fills both in when it writes the live file — the
Tailnet IP via `tailscale ip -4` (auto-detected, never hardcoded), the
password from its command-line argument. If no Tailnet IPv4 address can be
detected, the helper refuses to write the file at all (fail closed: no
Tailnet address means no RDP listener, rather than falling back to a wider
bind).

## Setting it up

```bash
# 1) Package
sudo dnf install -y krdp        # or your distro's equivalent

# 2) (if you don't have a certificate yet) generate one once via the KCM:
#    System Settings -> Remote Desktop -> Generate Certificate.
#    Result: ~/.local/share/krdpserver/server.{crt,key}

# 3) Write the live override from the template (fills in your Tailnet IP
#    and the password you pass; mode 600):
bin/msw-krdp-setup '<RDP-PASSWORD>'

# 4) Start + persist (a live action -> deliberately manual):
systemctl --user enable --now app-org.kde.krdpserver.service

# 5) Verify the bind -- MUST be your Tailnet address, NOT 0.0.0.0:
ss -tlnH 'sport = :3389'
#   -> LISTEN ... <TAILNET_IP>:3389 ... users:(("krdpserver",...))

# 6) Status detection in the widget:
msw-status --json | jq '.remote.rdp'
#   -> {"installed": true, "active": true}
```

## Connecting

Point an RDP client (e.g. FreeRDP, Remmina, the Windows RDP client) at your
machine's **Tailnet IP** (`tailscale ip -4`), with the username you set up
(typically `$(id -un)` on that machine) and the password you chose. Accept
the self-signed certificate once. Only reachable from within the Tailnet.

## Reverting

```bash
systemctl --user disable --now app-org.kde.krdpserver.service
rm ~/.config/systemd/user/app-org.kde.krdpserver.service.d/override.conf
systemctl --user daemon-reload
```
