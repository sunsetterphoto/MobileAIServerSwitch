/*
 * "Remote Access" tab: overview of all remote-access paths (SSH, Sunshine,
 * KDE Connect, RDP, VNC, Tailnet) and Wake-on-LAN, from msw-status --json:
 * status.remote. Read-only display + copyable Tailnet IP + WoL switch -- the
 * switch goes exclusively through ctrl.powerCmd() (msw-power, SSH-safe, see
 * PerformanceTab). No bare root/exec access: this file doesn't see
 * `root`/`exec` from main.qml (no global scope).
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: remoteAccessTab
    property var ctrl

    spacing: Kirigami.Units.smallSpacing

    // Local fallbacks until the first poll completes (ctrl.status.remote is
    // undefined until then) -- same pattern as PerformanceTab (gpuState/powerExtra).
    readonly property var r: (ctrl.status && ctrl.status.remote) || ({})
    readonly property var sshState: (r.ssh) || ({})
    readonly property var sunshineState: (r.sunshine) || ({})
    readonly property var tailscaleState: (r.tailscale) || ({})
    readonly property var kdeconnectState: (r.kdeconnect) || ({})
    readonly property var rdpState: (r.rdp) || ({})
    readonly property var vncState: (r.vnc) || ({})
    readonly property var wolState: (r.wol) || ({})

    // No tailnet ip -> Tailscale isn't set up / reachable; hide the whole
    // Tailnet section (StatusRow + copyable IP field below).
    readonly property bool tailscaleAvailable: remoteAccessTab.tailscaleState.active === true
        && !!remoteAccessTab.tailscaleState.ip4 && remoteAccessTab.tailscaleState.ip4 !== "?"

    // Reusable status dot: green = active, dimmed = inactive/off.
    component StatusDot: Rectangle {
        property bool on: false
        width: Kirigami.Units.gridUnit * 0.6
        height: width
        radius: width / 2
        color: on ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
    }

    // Reusable row: dot . name . detail (small, dimmed).
    component StatusRow: RowLayout {
        id: row
        property bool on: false
        property string label: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        StatusDot { on: row.on }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: row.label }
            PlasmaComponents3.Label {
                text: row.detail
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                visible: text.length > 0
            }
        }
    }

    StatusRow {
        on: remoteAccessTab.sshState.active === true
        label: "SSH"
        detail: ":22 · " + (remoteAccessTab.sshState.exposure || "—")
    }

    // Sunshine row: on/off switch like the WoL row (instead of StatusRow), so
    // a button fits on the right. Sunshine is an optional generic remote
    // method (not tied to any particular GPU); msw-status now emits
    // remote.sunshine.installed (mirroring rdp/vnc), so the row is hidden
    // entirely when Sunshine isn't installed -- same graceful-degradation
    // pattern as RDP/VNC.
    RowLayout {
        Layout.fillWidth: true
        visible: remoteAccessTab.sunshineState.installed === true
        spacing: Kirigami.Units.smallSpacing

        StatusDot { on: remoteAccessTab.sunshineState.active === true }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: "Sunshine" }
            PlasmaComponents3.Label {
                text: "Moonlight · " + (remoteAccessTab.sunshineState.exposure || "—")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }

        PlasmaComponents3.Button {
            text: remoteAccessTab.sunshineState.active ? "off" : "on"
            icon.name: remoteAccessTab.sunshineState.active ? "media-playback-stop" : "media-playback-start"
            onClicked: ctrl.runAndRefresh(
                "systemctl --user " + (remoteAccessTab.sunshineState.active ? "stop" : "start")
                + " app-dev.lizardbyte.app.Sunshine.service")
        }
    }

    StatusRow {
        on: remoteAccessTab.kdeconnectState.active === true
        label: "KDE Connect"
        detail: ":1716"
    }

    // RDP row: on/off switch like the WoL row (instead of StatusRow). Button
    // only shown when KRDP is installed -- otherwise there's no unit to start.
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        StatusDot { on: remoteAccessTab.rdpState.active === true }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: "RDP (KRDP)" }
            PlasmaComponents3.Label {
                text: !remoteAccessTab.rdpState.installed
                      ? "not installed"
                      : (remoteAccessTab.rdpState.active ? "running · :3389" : "installed, off")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }

        PlasmaComponents3.Button {
            visible: remoteAccessTab.rdpState.installed === true
            text: remoteAccessTab.rdpState.active ? "off" : "on"
            icon.name: remoteAccessTab.rdpState.active ? "media-playback-stop" : "media-playback-start"
            onClicked: ctrl.runAndRefresh(
                "systemctl --user " + (remoteAccessTab.rdpState.active ? "stop" : "start")
                + " app-org.kde.krdpserver.service")
        }
    }

    StatusRow {
        on: remoteAccessTab.vncState.active === true
        label: "VNC"
        detail: !remoteAccessTab.vncState.installed
                ? "not installed"
                : (remoteAccessTab.vncState.active ? "running · :5900" : "installed, off")
    }

    Kirigami.Separator { Layout.fillWidth: true; visible: remoteAccessTab.tailscaleAvailable }

    StatusRow {
        visible: remoteAccessTab.tailscaleAvailable
        on: remoteAccessTab.tailscaleState.active === true
        label: "Tailnet"
        detail: ""
    }

    // Copyable IP field: readOnly + selectByMouse, so the address can be
    // selected/copied without looking like an editable field (flat/
    // transparent background, normal text color).
    PlasmaComponents3.TextField {
        visible: remoteAccessTab.tailscaleAvailable
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        background: null
        color: Kirigami.Theme.textColor
        text: (remoteAccessTab.tailscaleState.ip4 || "—")
              + " (" + (remoteAccessTab.tailscaleState.host || "—")
              + ", " + (remoteAccessTab.tailscaleState.peers !== undefined
                        ? remoteAccessTab.tailscaleState.peers : "?")
              + " peers)"
    }

    Kirigami.Separator { Layout.fillWidth: true }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        StatusDot { on: remoteAccessTab.wolState.enabled === true }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: "Wake-on-LAN" }
            PlasmaComponents3.Label {
                // null = ethtool unreadable -> "unknown", never a made-up "off"
                text: remoteAccessTab.wolState.enabled === true
                      ? "Magic packet (" + remoteAccessTab.wolState.mode + ")"
                      : (remoteAccessTab.wolState.enabled === false ? "off" : "unknown")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }

        PlasmaComponents3.Button {
            text: remoteAccessTab.wolState.enabled ? "off" : "on"
            onClicked: ctrl.powerCmd(remoteAccessTab.wolState.enabled ? "wol off" : "wol on")
        }
    }

    Item { Layout.fillHeight: true }
}
