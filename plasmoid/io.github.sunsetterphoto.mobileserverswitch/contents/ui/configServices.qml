/*
 * Services: editable list backing config.json's top-level "services" array
 * (each {id,label,unit,scope,port} -- see config/config.example.json and
 * bin/msw-status's CONFIG_SERVICES loop). Stored as a single JSON-string
 * KConfigXT entry (servicesJson) because KConfigXT has no native "list of
 * objects" type; the row editor below parses/re-serializes it.
 *
 * Repeater-over-parsed-JSON + commit() pattern verified against the working
 * custom plasmoid io.github.sunsetterphoto.healthpanel's
 * ui/configPanel.qml (same "parse JSON into `items`, mutate a JS copy,
 * re-serialize on every change" approach for its panelLayout entry).
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property string cfg_servicesJson: "[]"
    property string cfg_servicesJsonDefault: "[]"

    // Live-parsed working copy; re-evaluated whenever cfg_servicesJson
    // changes (including the initial load from the stored config).
    property var items: parseServices(cfg_servicesJson)

    function parseServices(json) {
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }

    // Replaces one field on row `i`, keeping the others, then commits.
    function updateService(i, patch) {
        var cur = page.items[i];
        var next = { id: cur.id, label: cur.label, unit: cur.unit, scope: cur.scope, port: cur.port };
        for (var k in patch) next[k] = patch[k];
        var a = page.items.slice();
        a[i] = next;
        page.commit(a);
    }

    function commit(a) {
        items = a;
        cfg_servicesJson = JSON.stringify(a);
    }

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "Services shown in the Services tab. Each entry needs a stable ID, a systemd unit name, whether that unit is a user or system service, and the TCP port used for the exposure check (LAN/Tailnet/localhost)."
    }

    Repeater {
        model: page.items
        delegate: Kirigami.AbstractCard {
            id: card
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    QQC2.TextField {
                        Kirigami.FormData.label: "ID:"
                        Layout.fillWidth: true
                        text: card.modelData.id || ""
                        onTextEdited: page.updateService(card.index, { id: text })
                    }
                    QQC2.TextField {
                        Kirigami.FormData.label: "Label:"
                        Layout.fillWidth: true
                        text: card.modelData.label || ""
                        onTextEdited: page.updateService(card.index, { label: text })
                    }
                    QQC2.TextField {
                        Kirigami.FormData.label: "Systemd unit:"
                        Layout.fillWidth: true
                        placeholderText: "example.service"
                        text: card.modelData.unit || ""
                        onTextEdited: page.updateService(card.index, { unit: text })
                    }
                    QQC2.ComboBox {
                        id: scopeBox
                        Kirigami.FormData.label: "Scope:"
                        model: ["user", "system"]
                        currentIndex: card.modelData.scope === "system" ? 1 : 0
                        onActivated: page.updateService(card.index, { scope: currentText })
                    }
                    QQC2.SpinBox {
                        Kirigami.FormData.label: "Port:"
                        from: 1
                        to: 65535
                        value: card.modelData.port || 1
                        onValueModified: page.updateService(card.index, { port: value })
                    }
                }

                QQC2.Button {
                    text: "Remove"
                    icon.name: "list-remove"
                    Layout.alignment: Qt.AlignRight
                    onClicked: {
                        var a = page.items.slice();
                        a.splice(card.index, 1);
                        page.commit(a);
                    }
                }
            }
        }
    }

    QQC2.Button {
        text: "Add service"
        icon.name: "list-add"
        Layout.topMargin: Kirigami.Units.smallSpacing
        onClicked: {
            var a = page.items.slice();
            a.push({ id: "", label: "", unit: "", scope: "user", port: 8080 });
            page.commit(a);
        }
    }

    Item { Layout.fillHeight: true }
}
