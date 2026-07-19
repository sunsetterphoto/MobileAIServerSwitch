/*
 * "Firewall" tab: read-only status of the firewalld LAN zone
 * (status.firewall from msw-status --json) + per-app switches for the four
 * whitelisted apps (RDP/VNC/Sunshine/ComfyUI). Only the LAN zone
 * (TODO(task2): auto-detected LAN interfaces) is affected -- SSH and the
 * Tailnet (tailscale0, not assigned to any zone) are deliberately NOT
 * switchable and always stay reachable.
 *
 * Switching goes exclusively through ctrl.firewallCmd("block|allow <app>")
 * (msw-firewall, the privileged helper enforces the LAN restriction). No bare
 * root/exec access: this file doesn't see `root`/`exec` from main.qml (no
 * global scope between separate .qml files).
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: firewallTab
    property var ctrl

    spacing: Kirigami.Units.smallSpacing

    // Local fallback until the first poll completes (ctrl.status.firewall is
    // undefined until then) -- same pattern as RemoteAccessTab (r/sshState).
    readonly property var fw: (ctrl.status && ctrl.status.firewall)
        || ({ zone: null, lan_ifaces: [], high_ports_open: false, ssh_allowed: false, apps: {} })

    function appBlocked(id) {
        return !!(fw.apps && fw.apps[id] && fw.apps[id].blocked);
    }

    // The four whitelisted apps switchable via msw-firewall.
    readonly property var apps: [
        { id: "rdp",      label: "RDP",      detail: ":3389" },
        { id: "vnc",      label: "VNC",      detail: ":5900-5903" },
        { id: "sunshine", label: "Sunshine", detail: ":47984-48010" },
        { id: "comfyui",  label: "ComfyUI",  detail: ":8188" }
    ]

    // Reusable status dot: green = allowed, dimmed = blocked.
    // (visually identical to RemoteAccessTab.StatusDot -- no shared scope
    // between tabs, so redefined here.)
    component StatusDot: Rectangle {
        property bool on: false
        width: Kirigami.Units.gridUnit * 0.6
        height: width
        radius: width / 2
        color: on ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
    }

    // --- A. Status area (read-only) -------------------------------------------
    PlasmaComponents3.Label {
        text: "Firewall (LAN)"
        font.bold: true
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: Kirigami.Units.smallSpacing / 2
        columnSpacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.Label { text: "Zone:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: firewallTab.fw.zone || "?" }

        PlasmaComponents3.Label { text: "LAN interfaces:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: (firewallTab.fw.lan_ifaces || []).join(", ") || "—" }

        PlasmaComponents3.Label { text: "High ports (1025–65535):"; opacity: 0.7 }
        PlasmaComponents3.Label { text: firewallTab.fw.high_ports_open ? "open" : "blocked" }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "lock"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: "SSH: " + (firewallTab.fw.ssh_allowed ? "allowed" : "?") + " (not switchable)"
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: "The Tailnet is separate (tailscale0, no zone) and always stays reachable — "
              + "LAN blocks only affect the LAN interfaces above."
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- B. App blocks (the four whitelisted apps) -----------------------------
    Repeater {
        model: firewallTab.apps

        delegate: RowLayout {
            id: appRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            readonly property bool blocked: firewallTab.appBlocked(modelData.id)

            StatusDot { on: !appRow.blocked }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                PlasmaComponents3.Label { text: appRow.modelData.label + " " + appRow.modelData.detail }
                PlasmaComponents3.Label {
                    text: appRow.blocked ? "LAN: blocked" : "LAN: allowed"
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }

            PlasmaComponents3.Button {
                text: appRow.blocked ? "allow" : "block"
                icon.name: appRow.blocked ? "dialog-ok" : "network-disconnect"
                onClicked: ctrl.firewallCmd((appRow.blocked ? "allow " : "block ") + appRow.modelData.id)
            }
        }
    }

    Item { Layout.fillHeight: true }
}
