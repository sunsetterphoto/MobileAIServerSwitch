/*
 * Mode: server/laptop switch on/off, optional per-mode battery charge
 * thresholds, and which configured services to stop when switching to
 * laptop mode.
 *
 * The "stop on laptop" checklist reads the OTHER config page's live value
 * via `Plasmoid.configuration.servicesJson` (not a cross-page cfg_ alias --
 * config pages are independent component instances with no shared scope).
 * `Plasmoid` being accessible from a config page (via
 * `import org.kde.plasma.plasmoid`) is verified from
 * org.kde.desktopcontainment/ui/ConfigIcons.qml, which reads
 * `Plasmoid.configuration.icon` / `Plasmoid.pluginName` the same way.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

ColumnLayout {
    id: page

    property alias cfg_modeEnabled: modeEnabledCheck.checked
    property bool cfg_modeEnabledDefault: true

    property alias cfg_chargeThresholdsEnabled: chargeCheck.checked
    property bool cfg_chargeThresholdsEnabledDefault: false

    property alias cfg_chargeServer: chargeServerField.text
    property string cfg_chargeServerDefault: "40/80"
    property alias cfg_chargeLaptop: chargeLaptopField.text
    property string cfg_chargeLaptopDefault: "0/100"

    property string cfg_stopOnLaptopJson: "[]"
    property string cfg_stopOnLaptopJsonDefault: "[]"

    property var stopIds: parseIds(cfg_stopOnLaptopJson)
    readonly property var knownServices: parseServices(Plasmoid.configuration.servicesJson)

    function parseIds(json) {
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }
    function parseServices(json) {
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }
    function toggle(id, on) {
        var a = page.stopIds.slice();
        var i = a.indexOf(id);
        if (on && i < 0) a.push(id);
        if (!on && i >= 0) a.splice(i, 1);
        page.stopIds = a;
        page.cfg_stopOnLaptopJson = JSON.stringify(a);
    }

    spacing: Kirigami.Units.smallSpacing

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.CheckBox {
            id: modeEnabledCheck
            Kirigami.FormData.label: "Mode switch:"
            text: "Enable server/laptop mode switching"
        }
    }

    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.CheckBox {
            id: chargeCheck
            Kirigami.FormData.label: "Charge thresholds:"
            text: "Apply per-mode battery charge thresholds (only if the hardware supports it)"
        }
        QQC2.TextField {
            id: chargeServerField
            Kirigami.FormData.label: "Server mode:"
            placeholderText: "40/80"
            enabled: chargeCheck.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        }
        QQC2.TextField {
            id: chargeLaptopField
            Kirigami.FormData.label: "Laptop mode:"
            placeholderText: "0/100"
            enabled: chargeCheck.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        }
    }

    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

    QQC2.Label {
        Layout.fillWidth: true
        text: "Services to stop when switching to laptop mode:"
    }

    ColumnLayout {
        visible: page.knownServices.length > 0
        Repeater {
            model: page.knownServices
            delegate: QQC2.CheckBox {
                required property var modelData
                text: modelData.label || modelData.id
                checked: page.stopIds.indexOf(modelData.id) >= 0
                onToggled: page.toggle(modelData.id, checked)
            }
        }
    }
    QQC2.Label {
        visible: page.knownServices.length === 0
        opacity: 0.7
        text: "No services configured yet -- add some on the Services page first."
    }

    Item { Layout.fillHeight: true }
}
