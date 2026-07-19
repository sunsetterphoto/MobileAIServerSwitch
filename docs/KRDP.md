# KRDP — Wayland-natives RDP, nur im Tailnet erreichbar

Verifizierte Einrichtung auf `t15g2nsa` (Fedora 44, KDE Plasma 6.7.2 Wayland).
Stand: 2026-07-19. Alle Werte am echten System geprüft (nicht geraten).

## Was & warum

- **Paket:** `krdp-6.7.3-1.fc44` → Binary `/usr/bin/krdpserver`, User-Unit
  `app-org.kde.krdpserver.service`, KCM `kcm_krdpserver` (System Settings →
  „Entfernte Arbeitsfläche").
- **Ziel:** RDP-Zugang zum laufenden Desktop, **ausschließlich über das Tailnet**
  (`100.75.62.108:3389`), nie auf `0.0.0.0`.

## Warum ein systemd-User-Override (statt KCM)

`krdpserver --help` zeigt: die Bind-Adresse kommt nur über `--address` (Default
`0.0.0.0`). Der KCM speichert Nutzer/Passwort zwar sicher in KWallet, bietet aber
**keine** Adress-Einstellung. Für die Tailnet-Bindung brauchen wir also explizite
Flags → Drop-In-Override der Stock-Unit:

```
~/.config/systemd/user/app-org.kde.krdpserver.service.d/override.conf   (Mode 600)
```

Der Override ersetzt nur `ExecStart`; Reihenfolge/Umgebung der Stock-Unit
(`After=plasma-*`, `WantedBy=plasma-workspace.target`) bleiben erhalten, damit der
Dienst in der grafischen Sitzung mit gültigem `WAYLAND_DISPLAY`/KWin-Zugriff läuft.

Effektiver Aufruf:

```
/usr/bin/krdpserver --plasma \
  --address 100.75.62.108 --port 3389 \
  --certificate  %h/.local/share/krdpserver/server.crt \
  --certificate-key %h/.local/share/krdpserver/server.key \
  --username samuel --password <geheim>
```

- `--plasma`: KWin-native Screencast + Fake-Input statt XDG-RemoteDesktop-Portal
  → **kein** Consent-Dialog beim Verbinden (unbeaufsichtigter Serverbetrieb).
- **TLS-Zertifikat:** einmalig erzeugt, `CN=t15g2nsa`, gültig bis 2036, unter
  `~/.local/share/krdpserver/server.{crt,key}`. Selbstsigniert → im RDP-Client
  einmalig bestätigen.

## Sicherheit: Passwort nicht im Repo

`krdpserver` nimmt das Passwort nur per `-p/--password` (kein `--password-file`,
keine Env-Var). Es steht daher in der Live-Override (Mode 600) und ist in der
Prozess-Cmdline (`ps`) für den **eigenen** Nutzer sichtbar. Auf einem
Single-User-Server akzeptabel; die Datei wird jedoch **nie** committet.

Im Repo liegt nur die **Vorlage** mit Platzhalter:
`system/systemd-user/app-org.kde.krdpserver.service.d/override.conf.template`.

## Einrichtung reproduzieren

```bash
# 1) Paket
sudo dnf install -y krdp

# 2) (falls noch kein Zertifikat) einmalig über den KCM erzeugen:
#    System Settings → Entfernte Arbeitsfläche → Zertifikat erzeugen.
#    Ergebnis: ~/.local/share/krdpserver/server.{crt,key}

# 3) Live-Override aus der Vorlage schreiben (Passwort einsetzen, Mode 600):
bin/t15g-krdp-setup '<RDP-PASSWORT>'

# 4) Starten + persistent (Live-Eingriff -> bewusst manuell):
systemctl --user enable --now app-org.kde.krdpserver.service

# 5) Bind verifizieren -- MUSS Tailnet sein, NICHT 0.0.0.0:
ss -tlnH 'sport = :3389'
#   -> LISTEN ... 100.75.62.108:3389 ... users:(("krdpserver",...))

# 6) Status-Erkennung im Widget:
t15g-status --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["remote"]["rdp"])'
#   -> {'installed': True, 'active': True}
```

## Verbinden

RDP-Client (z. B. FreeRDP/Remmina/Windows-Client) auf **`100.75.62.108`**,
Benutzer `samuel`, Passwort wie gesetzt. Selbstsigniertes Zertifikat einmalig
akzeptieren. Nur aus dem Tailnet erreichbar.

## Zurücknehmen

```bash
systemctl --user disable --now app-org.kde.krdpserver.service
rm ~/.config/systemd/user/app-org.kde.krdpserver.service.d/override.conf
systemctl --user daemon-reload
```
