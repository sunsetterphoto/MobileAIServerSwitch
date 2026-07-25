/*
 * General settings: CLI directory override + which tabs are shown.
 *
 * Binding convention verified against installed Plasma 6 plasmoids
 * (org.kde.desktopcontainment/ui/ConfigIcons.qml,
 * org.kde.plasma.systemmonitor/ui/config/ConfigAppearance.qml) and the
 * working custom plasmoid io.github.sunsetterphoto.healthpanel: the config
 * page's root Item exposes `property alias cfg_<entryName>: <widget>.<prop>`
 * (or a plain `property <type> cfg_<entryName>` for values not tied 1:1 to a
 * single widget property) -- the Plasma config dialog finds these by name
 * and binds them to the KConfigXT entry declared in config/main.xml. This is
 * NOT the `kcfg_<name>`-named-widget convention (that belongs to
 * KCM/KConfigDialogManager-style pages); Plasma applet ConfigModel pages use
 * `cfg_`.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property alias cfg_binPath: binPathField.text
    property string cfg_binPathDefault: ""

    property alias cfg_showPerformance: showPerformanceCheck.checked
    property bool cfg_showPerformanceDefault: true
    property alias cfg_showMode: showModeCheck.checked
    property bool cfg_showModeDefault: true
    property alias cfg_showNetwork: showNetworkCheck.checked
    property bool cfg_showNetworkDefault: true
    property alias cfg_showRemote: showRemoteCheck.checked
    property bool cfg_showRemoteDefault: true
    property alias cfg_showServices: showServicesCheck.checked
    property bool cfg_showServicesDefault: true
    property alias cfg_showFirewall: showFirewallCheck.checked
    property bool cfg_showFirewallDefault: true
    property alias cfg_showNotes: showNotesCheck.checked
    property bool cfg_showNotesDefault: true

    spacing: Kirigami.Units.smallSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            id: binPathField
            Kirigami.FormData.label: "CLI directory:"
            placeholderText: "auto ($HOME/.local/bin, falling back to /usr/local/bin)"
            Layout.fillWidth: true
        }
    }

    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

    QQC2.Label {
        Layout.fillWidth: true
        text: "Visible tabs (Overview is always shown):"
    }
    QQC2.CheckBox { id: showPerformanceCheck; text: "Performance" }
    QQC2.CheckBox { id: showModeCheck; text: "Mode" }
    QQC2.CheckBox { id: showNetworkCheck; text: "Network" }
    QQC2.CheckBox { id: showRemoteCheck; text: "Remote Access" }
    QQC2.CheckBox { id: showServicesCheck; text: "Services" }
    QQC2.CheckBox { id: showFirewallCheck; text: "Firewall" }
    QQC2.CheckBox { id: showNotesCheck; text: "Notes" }

    Item { Layout.fillHeight: true }
}
