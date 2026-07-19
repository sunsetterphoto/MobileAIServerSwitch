/*
 * "Overview" tab: compact, read-only summary of all relevant state at a
 * glance -- mode, performance, dGPU, battery/AC, Tailnet IP, SSH/Sunshine
 * status, number of active services, WoL status. Default tab (index 0 in
 * main.qml) -- the popup opens here.
 *
 * READ-ONLY: no CLI calls except ctrl.refresh() (the Refresh button). No
 * ctrl.perfCmd/powerCmd/runAndRefresh/switchMode here.
 *
 * Sections are clickable and jump to the corresponding detail tab via the
 * navigate(index) signal. This file doesn't see `tabs` from main.qml (no
 * global scope between separate .qml files) -- so it does NOT touch
 * tabs.currentIndex directly, but passes the signal upward instead. main.qml
 * wires it up as:
 *   OverviewTab { ctrl: root; onNavigate: (i) => tabs.currentIndex = i }
 *
 * All data comes via ctrl.* (property var ctrl = root from main.qml),
 * including local fallbacks following the same pattern as PerformanceTab/
 * RemoteAccessTab, so nothing accesses undefined before the first refresh()
 * (ctrl.status === {}).
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: overviewTab

    // Reference to the root PlasmoidItem from main.qml.
    property var ctrl

    // Jump into a detail tab (main.qml sets tabs.currentIndex accordingly).
    signal navigate(int index)

    spacing: Kirigami.Units.smallSpacing

    // Local fallbacks until the first poll completes (ctrl.status is still {}
    // until then) -- same pattern as PerformanceTab (gpuState/powerExtra) and
    // RemoteAccessTab (r/sshState/...).
    readonly property var gpuState: (ctrl.status && ctrl.status.gpu) || ({ present: false, awake: false, watts: null, dstate: "?" })
    readonly property var powerState: (ctrl.status && ctrl.status.power) || ({})
    readonly property var remote: (ctrl.status && ctrl.status.remote) || ({})
    readonly property var sshState: (remote.ssh) || ({})
    readonly property var sunshineState: (remote.sunshine) || ({})
    readonly property var tailscaleState: (remote.tailscale) || ({})
    readonly property var wolState: (remote.wol) || ({})
    readonly property var services: (ctrl.status && ctrl.status.services) || []

    readonly property int servicesActive: {
        var n = 0;
        for (var i = 0; i < services.length; i++)
            if (services[i].active === true) n++;
        return n;
    }

    // Reusable status dot: green = active, dimmed = inactive/off.
    // (visually identical to RemoteAccessTab.StatusDot -- no shared scope
    // between tabs, so redefined here.)
    component StatusDot: Rectangle {
        property bool on: false
        width: Kirigami.Units.gridUnit * 0.6
        height: width
        radius: width / 2
        color: on ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
    }

    // Reusable row: dot . name . detail (small, dimmed).
    component StatusRow: RowLayout {
        id: row
        property bool on: false
        property string label: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        StatusDot { on: row.on }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: row.label }
            PlasmaComponents3.Label {
                text: row.detail
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                visible: text.length > 0
            }
        }
    }

    // --- Mode (jumps to Mode tab, index 2) -----------------------------------
    Item {
        Layout.fillWidth: true
        implicitHeight: modeRow.implicitHeight

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: overviewTab.navigate(2)
        }

        RowLayout {
            id: modeRow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: ctrl.modeIcon(ctrl.mode)
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                PlasmaComponents3.Label { text: ctrl.modeLabel(ctrl.mode); font.bold: true }
                PlasmaComponents3.Label {
                    text: "Battery " + (ctrl.battery >= 0 ? ctrl.battery + " %" : "?")
                          + " · " + (overviewTab.powerState.ac ? "AC on" : "AC off")
                          + " · charge thresholds " + ctrl.charge
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Performance + dGPU (jumps to Performance tab, index 1) --------------
    Item {
        Layout.fillWidth: true
        implicitHeight: perfGrid.implicitHeight

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: overviewTab.navigate(1)
        }

        GridLayout {
            id: perfGrid
            anchors.left: parent.left
            anchors.right: parent.right
            columns: 2
            rowSpacing: Kirigami.Units.smallSpacing / 2
            columnSpacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label { text: "Performance:"; opacity: 0.7 }
            PlasmaComponents3.Label { text: ctrl.perfProfile + " · " + ctrl.maxPerfPct + " %" }

            // dGPU row: hidden entirely when there's no discrete GPU
            // (msw-status gpu.present). Both cells share the same visible
            // condition so the GridLayout reflows cleanly without a gap.
            PlasmaComponents3.Label {
                text: "dGPU:"; opacity: 0.7
                visible: overviewTab.gpuState.present === true
            }
            PlasmaComponents3.Label {
                visible: overviewTab.gpuState.present === true
                text: overviewTab.gpuState.awake
                      ? "▲ " + (overviewTab.gpuState.watts !== null && overviewTab.gpuState.watts !== undefined
                                ? overviewTab.gpuState.watts + " W" : "active")
                        + " (" + overviewTab.gpuState.dstate + ")"
                      : "asleep (" + overviewTab.gpuState.dstate + ")"
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Remote access: SSH/Sunshine status, Tailnet IP, WoL status ---------
    // (jumps to Remote Access tab, index 3)
    Item {
        Layout.fillWidth: true
        implicitHeight: remoteCol.implicitHeight

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: overviewTab.navigate(3)
        }

        ColumnLayout {
            id: remoteCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Kirigami.Units.smallSpacing

            StatusRow {
                on: overviewTab.sshState.active === true
                label: "SSH"
                detail: overviewTab.sshState.active ? "running" : "off"
            }
            StatusRow {
                on: overviewTab.sunshineState.active === true
                label: "Sunshine"
                detail: overviewTab.sunshineState.active ? "running" : "off"
            }
            PlasmaComponents3.Label {
                visible: overviewTab.tailscaleState.active === true
                         && !!overviewTab.tailscaleState.ip4 && overviewTab.tailscaleState.ip4 !== "?"
                text: "Tailnet: " + (overviewTab.tailscaleState.ip4 || "—")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
            StatusRow {
                on: overviewTab.wolState.enabled === true
                label: "Wake-on-LAN"
                detail: overviewTab.wolState.enabled ? "on" : "off"
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Services (jumps to Services tab, index 4) ----------------------------
    Item {
        Layout.fillWidth: true
        implicitHeight: servicesRow.implicitHeight

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: overviewTab.navigate(4)
        }

        RowLayout {
            id: servicesRow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label { text: "Services:"; opacity: 0.7 }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: overviewTab.servicesActive + "/" + overviewTab.services.length + " active"
            }
        }
    }

    Item { Layout.fillHeight: true }

    PlasmaComponents3.Button {
        Layout.fillWidth: true
        flat: true
        icon.name: "view-refresh"
        text: "Refresh"
        onClicked: ctrl.refresh()
    }
}
