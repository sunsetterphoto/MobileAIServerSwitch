/*
 * Mode: only the global on/off for profile switching remains here.
 *
 * Everything per-mode (charge thresholds, services to stop, ...) moved to
 * the Profiles page (configProfiles.qml), which edits the generic
 * profilesJson map. The old kcfg keys (chargeThresholdsEnabled,
 * chargeServer, chargeLaptop, stopOnLaptopJson) intentionally stay in
 * main.xml WITHOUT any UI: main.qml's migrateLegacyProfileSettings() reads
 * them once via Plasmoid.configuration.<name> -- which works without a
 * cfg_ alias on any page -- and folds them into profilesJson.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property alias cfg_modeEnabled: modeEnabledCheck.checked
    property bool cfg_modeEnabledDefault: true

    spacing: Kirigami.Units.smallSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.CheckBox {
            id: modeEnabledCheck
            Kirigami.FormData.label: "Mode switch:"
            text: "Enable profile switching"
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "Per-mode settings (charge thresholds, services, …) have moved to the Profiles page."
    }

    Item { Layout.fillHeight: true }
}
