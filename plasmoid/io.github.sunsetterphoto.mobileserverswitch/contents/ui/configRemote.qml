/*
 * Remote Access: RDP (KRDP) enable state + bind target. These map to
 * config.json's remote.rdp.{enabled,bind}. Note: as of this task, no msw-*
 * CLI reads remote.rdp.* yet (grepped bin/ and system/ -- only
 * config/config.example.json documents the shape); this page still writes
 * it so the contract is ready once a consumer is added. See docs/KRDP.md
 * for the actual KRDP server setup (password, systemd override), which is
 * out of scope for this settings page.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property string cfg_rdpEnabled: "auto"
    property string cfg_rdpEnabledDefault: "auto"
    property string cfg_rdpBind: "tailscale"
    property string cfg_rdpBindDefault: "tailscale"

    spacing: Kirigami.Units.smallSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.ComboBox {
            id: rdpEnabledBox
            Kirigami.FormData.label: "RDP (KRDP):"
            textRole: "text"
            valueRole: "value"
            model: [
                { text: "Auto-detect", value: "auto" },
                { text: "On", value: "on" },
                { text: "Off", value: "off" }
            ]
            onActivated: page.cfg_rdpEnabled = currentValue
            Component.onCompleted: currentIndex = indexOfValue(page.cfg_rdpEnabled)
        }

        QQC2.ComboBox {
            id: rdpBindBox
            Kirigami.FormData.label: "Bind to:"
            textRole: "text"
            valueRole: "value"
            model: [
                { text: "Tailscale (recommended)", value: "tailscale" },
                { text: "LAN", value: "lan" },
                { text: "Custom", value: "custom" }
            ]
            onActivated: page.cfg_rdpBind = currentValue
            Component.onCompleted: currentIndex = indexOfValue(page.cfg_rdpBind)
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "See docs/KRDP.md for setting up the KRDP server itself. This page only controls what the plasmoid writes to config.json."
    }

    Item { Layout.fillHeight: true }
}
