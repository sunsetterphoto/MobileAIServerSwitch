/*
 * "Mode" tab: server/laptop switching -- moved here 1:1 from the former
 * fullRepresentation. Logic unchanged, only switched to `ctrl.*` instead of
 * `root.*` because separate .qml files don't see main.qml's `root`.
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: modeTab

    // Reference to the root PlasmoidItem from main.qml (status, exec, functions).
    property var ctrl

    spacing: Kirigami.Units.smallSpacing

    // Header: current mode
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        Kirigami.Icon {
            source: ctrl.modeIcon(ctrl.mode)
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
        }
        ColumnLayout {
            spacing: 0
            PlasmaExtras.Heading {
                level: 3
                text: ctrl.modeLabel(ctrl.mode)
            }
            PlasmaComponents3.Label {
                text: "Operating mode"
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // Status rows
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.Label { text: "Sunshine:"; opacity: 0.7 }
        PlasmaComponents3.Label {
            // Sunshine is a generic optional remote-streaming method, not
            // tied to any particular GPU -- so this just reports whether the
            // service is running, without machine-specific assumptions.
            text: ctrl.sunshine === "active" ? "running" : ctrl.sunshine
            color: ctrl.sunshine === "active" ? Kirigami.Theme.positiveTextColor
                                              : Kirigami.Theme.textColor
        }
        PlasmaComponents3.Label { text: "Charge thresholds:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: ctrl.charge }
        PlasmaComponents3.Label { text: "Battery:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: ctrl.battery >= 0 ? ctrl.battery + " %" : "?" }
    }

    Item { Layout.fillHeight: true }

    // Warning: Sunshine is running and we would switch to laptop
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: confirmRow.visible
        wrapMode: Text.WordWrap
        text: ctrl.sunshine === "active"
              ? "Warning: Sunshine is currently running — laptop mode will stop the stream."
              : "Laptop mode stops Sunshine and the server services."
        color: Kirigami.Theme.neutralTextColor
    }

    // Confirmation row (only when switching to laptop)
    RowLayout {
        id: confirmRow
        Layout.fillWidth: true
        visible: false
        PlasmaComponents3.Button {
            Layout.fillWidth: true
            icon.name: "dialog-ok"
            text: "Yes, switch to laptop"
            enabled: !ctrl.busy
            onClicked: {
                confirmRow.visible = false;
                ctrl.switchMode("laptop");
            }
        }
        PlasmaComponents3.Button {
            Layout.fillWidth: true
            icon.name: "dialog-cancel"
            text: "Cancel"
            onClicked: confirmRow.visible = false
        }
    }

    // Main switch button
    PlasmaComponents3.Button {
        Layout.fillWidth: true
        visible: !confirmRow.visible
        enabled: !ctrl.busy
        icon.name: ctrl.isServer ? "computer-laptop" : "network-server"
        text: ctrl.busy ? "Please wait …"
                        : (ctrl.isServer ? "Switch to laptop" : "Switch to server")
        onClicked: {
            if (ctrl.isServer) {
                // Switching to laptop -> confirm first
                confirmRow.visible = true;
            } else {
                // Switching to server is uncritical -> immediate
                ctrl.switchMode("server");
            }
        }
    }

    PlasmaComponents3.Button {
        Layout.fillWidth: true
        flat: true
        icon.name: "view-refresh"
        text: "Refresh"
        onClicked: ctrl.refresh()
    }
}
