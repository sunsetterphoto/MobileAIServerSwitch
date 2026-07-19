/*
 * Network overrides: LAN interfaces / Tailscale / firewall zone.
 * "auto" (the default for all three) means runtime auto-detection, exactly
 * like an absent config.json key -- see bin/msw-config's cfg_or_detect().
 * Only a non-"auto" value here overrides detection.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property alias cfg_lanInterfaces: lanInterfacesField.text
    property string cfg_lanInterfacesDefault: "auto"

    // ComboBox has no single widget property that maps 1:1 to the string
    // value, so this is a plain (non-alias) property synced manually --
    // same pattern as healthpanel's configGeneral.qml cfg_language.
    property string cfg_tailscale: "auto"
    property string cfg_tailscaleDefault: "auto"

    property alias cfg_firewallZone: firewallZoneField.text
    property string cfg_firewallZoneDefault: "auto"

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "\"auto\" runs live detection on every read. Only override a value here if detection picks the wrong interface or zone on this system."
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            id: lanInterfacesField
            Kirigami.FormData.label: "LAN interfaces:"
            placeholderText: "auto"
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: tailscaleBox
            Kirigami.FormData.label: "Tailscale:"
            textRole: "text"
            valueRole: "value"
            model: [
                { text: "Auto-detect", value: "auto" },
                { text: "Off", value: "off" }
            ]
            onActivated: page.cfg_tailscale = currentValue
            Component.onCompleted: currentIndex = indexOfValue(page.cfg_tailscale)
        }

        QQC2.TextField {
            id: firewallZoneField
            Kirigami.FormData.label: "Firewall zone:"
            placeholderText: "auto"
            Layout.fillWidth: true
        }
    }

    Item { Layout.fillHeight: true }
}
