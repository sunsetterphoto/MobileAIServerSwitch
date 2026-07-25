/*
 * "Firewall" tab: read-only status of the firewalld LAN zone
 * (status.firewall from msw-status --json) + per-app switches for whichever
 * apps are config-driven (config.firewall.apps -- default rdp+vnc, see
 * msw-status/msw-firewall). Only the LAN zone (auto-detected LAN interfaces)
 * is affected -- SSH and the Tailnet (tailscale0, not assigned to any zone)
 * are deliberately NOT switchable and always stay reachable.
 *
 * The app rows are rendered entirely from ctrl.status.firewall.apps (an
 * object keyed by app id, each value {blocked,label,ports} -- see
 * msw-status), NOT a hardcoded list: whatever the backend's config-driven
 * whitelist currently is, is exactly what shows up here, so there are never
 * dead controls for apps the backend would reject.
 *
 * Switching goes exclusively through ctrl.firewallCmd("block|allow <app>")
 * (msw-firewall, the privileged helper enforces the LAN restriction). No bare
 * root/exec access: this file doesn't see `root`/`exec` from main.qml (no
 * global scope between separate .qml files).
 *
 * Graceful degradation: the Firewall TabButton in main.qml is always visible
 * (no more hide-the-tab -- that left a non-collapsing blank gap in the
 * ListView-based TabBar when firewalld was absent). Instead, this tab itself
 * shows a clear "requires firewalld" message in place of the firewall
 * content whenever status.firewall.zone is empty/null -- same visibility
 * pattern as before (an inner `available` ColumnLayout, not bound directly
 * on this file's root item): this root ColumnLayout is StackLayout's direct
 * child in main.qml, and StackLayout manages its direct children's `visible`
 * property itself (imperatively, based on currentIndex), which would
 * silently clear any `visible:` binding set here at this level. The inner
 * ColumnLayout is a grandchild instead, so no such conflict applies.
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

    // firewalld not present at all (zone stays null when firewall-cmd is
    // missing or firewalld isn't running -- see msw-status).
    readonly property bool available: !!firewallTab.fw.zone

    // App ids present in the config-driven status (object keys of
    // status.firewall.apps), sorted for a stable display order.
    readonly property var appIds: Object.keys(firewallTab.fw.apps || {}).sort()

    function appEntry(id) {
        return (firewallTab.fw.apps && firewallTab.fw.apps[id]) || ({ blocked: false, label: id, ports: "" });
    }

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

    // Fallback hint: firewalld isn't present on this system at all.
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !firewallTab.available
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.7
        text: "Firewall control requires firewalld (not detected on this system)."
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: firewallTab.available
        spacing: Kirigami.Units.smallSpacing

        // --- A. Status area (read-only) ---------------------------------------
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
                // false is a real firewalld answer, not a missing one -> say so
                text: "SSH: " + (firewallTab.fw.ssh_allowed === true ? "allowed"
                                 : (firewallTab.fw.ssh_allowed === false ? "blocked" : "?"))
                      + " (not switchable)"
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

        // --- B. App blocks (config-driven -- see msw-status/msw-firewall) ------
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: firewallTab.appIds.length === 0
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: "No firewall-switchable apps configured."
        }

        Repeater {
            model: firewallTab.appIds

            delegate: RowLayout {
                id: appRow
                required property string modelData
                readonly property var entry: firewallTab.appEntry(modelData)
                readonly property bool blocked: !!entry.blocked

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                StatusDot { on: !appRow.blocked }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        text: appRow.entry.label + (appRow.entry.ports ? " :" + appRow.entry.ports : "")
                    }
                    PlasmaComponents3.Label {
                        text: appRow.blocked ? "LAN: blocked" : "LAN: allowed"
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }
                }

                PlasmaComponents3.Button {
                    text: appRow.blocked ? "allow" : "block"
                    icon.name: appRow.blocked ? "dialog-ok" : "network-disconnect"
                    onClicked: ctrl.firewallCmd((appRow.blocked ? "allow " : "block ") + appRow.modelData)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
