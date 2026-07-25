/*
 * "Network" tab: how this machine is reachable right now -- which interface
 * carries the default route, which addresses each interface has, and which
 * resolvers are in use. Read-only; everything comes from msw-status --json:
 * status.network (see bin/msw-status).
 *
 * Two values look "wrong" at first glance but are correct and must not be
 * "fixed" here: a tailnet interface (kind "tailnet", e.g. tailscale0) can
 * report up:true while its kernel operstate is UNKNOWN -- normal for tun
 * devices. A virtual interface (kind "virtual", e.g. virbr0) can report
 * up:false while administratively up -- it simply has no carrier. Both
 * come straight from msw-status; this tab only renders them.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: networkTab
    property var ctrl
    spacing: Kirigami.Units.smallSpacing

    readonly property var net: (ctrl.status && ctrl.status.network) || ({})
    readonly property var ifaces: net.interfaces || []
    // Physical first, virtual last: virbr0 is not a way in.
    readonly property var sortedIfaces: ifaces.slice().sort(function(a, b) {
        var av = a.kind === "virtual" ? 1 : 0;
        var bv = b.kind === "virtual" ? 1 : 0;
        return av - bv;
    })

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: "Host: " + (networkTab.net.hostname || "?")
        font.bold: true
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: networkTab.net.default
              ? "Default route: " + networkTab.net.default.iface
                + (networkTab.net.default.gateway ? " via " + networkTab.net.default.gateway : "")
                + (networkTab.net.default.ip4 ? " (" + networkTab.net.default.ip4 + ")" : "")
              : "No default route"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        visible: (networkTab.net.dns || []).length > 0
        text: "DNS: " + (networkTab.net.dns || []).join(", ")
    }

    Kirigami.Separator { Layout.fillWidth: true }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: networkTab.ifaces.length === 0
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "No interface data (is the `ip` command available?)"
    }

    Repeater {
        model: networkTab.sortedIfaces
        delegate: ColumnLayout {
            id: ifaceRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 0.6
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.6
                    radius: width / 2
                    color: ifaceRow.modelData.up ? Kirigami.Theme.positiveTextColor
                                                 : Kirigami.Theme.disabledTextColor
                }
                PlasmaComponents3.Label {
                    text: ifaceRow.modelData.name
                    font.bold: ifaceRow.modelData.is_default === true
                }
                PlasmaComponents3.Label {
                    text: ifaceRow.modelData.kind + (ifaceRow.modelData.is_default ? " · default route" : "")
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    Layout.fillWidth: true
                }
            }

            // Addresses are selectable so they can be copied straight out.
            // Plain QtQuick TextEdit (not PlasmaComponents3 -- that module has
            // no TextEdit, only TextField/TextArea), colored to match the
            // Plasma theme by hand.
            TextEdit {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                visible: text.length > 0
                readOnly: true
                selectByMouse: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                selectionColor: Kirigami.Theme.highlightColor
                text: (ifaceRow.modelData.ip4 || []).concat(ifaceRow.modelData.ip6 || []).join("  ")
            }
            PlasmaComponents3.Label {
                Layout.leftMargin: Kirigami.Units.gridUnit
                visible: (ifaceRow.modelData.ip4 || []).length === 0 && (ifaceRow.modelData.ip6 || []).length === 0
                text: "no address"
                opacity: 0.5
                font: Kirigami.Theme.smallFont
            }
            PlasmaComponents3.Label {
                Layout.leftMargin: Kirigami.Units.gridUnit
                visible: !!ifaceRow.modelData.mac
                text: ifaceRow.modelData.mac || ""
                opacity: 0.5
                font: Kirigami.Theme.smallFont
            }
        }
    }

    Item { Layout.fillHeight: true }
}
