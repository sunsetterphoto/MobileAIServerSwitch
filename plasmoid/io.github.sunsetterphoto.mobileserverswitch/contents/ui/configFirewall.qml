/*
 * Firewall: editable app -> port whitelist backing config.json's
 * "firewall.apps" array (each {id, ports_tcp?, ports_udp?} -- see
 * system/usr-local-sbin/msw-firewall-apply's add_ports()). Same
 * parse/mutate/re-serialize pattern as configServices.qml.
 *
 * Hard safety invariant (documented, not re-implemented here): the
 * privileged helper msw-firewall-apply refuses ssh/22/tailscale/tailscale0
 * unconditionally regardless of what this whitelist contains -- this page
 * cannot weaken that guard, it only edits the allow-list for everything
 * else.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page

    property string cfg_firewallAppsJson: "[]"
    property string cfg_firewallAppsJsonDefault: '[{"id":"rdp","ports_tcp":"3389"},{"id":"vnc","ports_tcp":"5900-5903"}]'

    property var items: parseApps(cfg_firewallAppsJson)

    function parseApps(json) {
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }
    function updateApp(i, patch) {
        var cur = page.items[i];
        var next = { id: cur.id, ports_tcp: cur.ports_tcp, ports_udp: cur.ports_udp };
        for (var k in patch) next[k] = patch[k];
        var a = page.items.slice();
        a[i] = next;
        page.commit(a);
    }
    function commit(a) {
        items = a;
        cfg_firewallAppsJson = JSON.stringify(a);
    }

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "Apps that can be individually blocked from LAN access in the Firewall tab. \"ssh\", \"22\" and \"tailscale\" can never be listed here -- the privileged helper refuses them unconditionally, no matter what is entered."
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
                        onTextEdited: page.updateApp(card.index, { id: text })
                    }
                    QQC2.TextField {
                        Kirigami.FormData.label: "TCP ports:"
                        Layout.fillWidth: true
                        placeholderText: "3389 or 5900-5903"
                        text: card.modelData.ports_tcp || ""
                        onTextEdited: page.updateApp(card.index, { ports_tcp: text })
                    }
                    QQC2.TextField {
                        Kirigami.FormData.label: "UDP ports:"
                        Layout.fillWidth: true
                        placeholderText: "(optional)"
                        text: card.modelData.ports_udp || ""
                        onTextEdited: page.updateApp(card.index, { ports_udp: text })
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
        text: "Add app"
        icon.name: "list-add"
        Layout.topMargin: Kirigami.Units.smallSpacing
        onClicked: {
            var a = page.items.slice();
            a.push({ id: "", ports_tcp: "", ports_udp: "" });
            page.commit(a);
        }
    }

    Item { Layout.fillHeight: true }
}
