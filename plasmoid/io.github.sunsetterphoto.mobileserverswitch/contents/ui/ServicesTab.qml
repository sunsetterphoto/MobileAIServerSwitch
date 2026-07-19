/*
 * "Services" tab -- list of all services (msw-status --json: status.services)
 * with a status dot, port/exposure and start/stop.
 *
 * Separate component: does NOT see `root`/`exec` from main.qml (no global
 * scope) -- so access exclusively via `ctrl.`. For arbitrary systemctl
 * commands main.qml provides `ctrl.runAndRefresh(cmd)` (exec + refresh live
 * in main.qml's root scope).
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    property var ctrl

    spacing: Kirigami.Units.smallSpacing

    // The unit name comes straight from the service object (msw-status
    // --json carries `unit` per config.services entry; no hardcoded table).
    function toggle(svc) {
        var action = svc.active ? "stop" : "start";
        var unit = svc.unit;
        if (!unit) return;   // malformed entry -> don't run systemctl without a unit
        var cmd = svc.scope === "system"
            ? "sudo -n systemctl " + action + " " + unit
            : "systemctl --user " + action + " " + unit;
        ctrl.runAndRefresh(cmd);
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !((ctrl.status.services) || []).length
        text: "No services configured -- add them in settings"
        opacity: 0.7
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    Repeater {
        model: (ctrl.status.services) || []

        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                width: Kirigami.Units.gridUnit * 0.6
                height: width
                radius: width / 2
                color: modelData.active ? Kirigami.Theme.positiveTextColor
                                         : Kirigami.Theme.disabledTextColor
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    text: modelData.label
                }
                PlasmaComponents3.Label {
                    text: ":" + modelData.port + "  ·  " + (modelData.exposure || "—")
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }

            PlasmaComponents3.Button {
                text: modelData.active ? "Stop" : "Start"
                icon.name: modelData.active ? "media-playback-stop" : "media-playback-start"
                onClicked: toggle(modelData)
            }
        }
    }

    Item { Layout.fillHeight: true }
}
