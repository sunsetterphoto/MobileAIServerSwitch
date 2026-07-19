/*
 * "Performance" tab: 3 presets (Power saver/Balanced/Performance) + fine
 * CPU-cap slider + turbo/profile display. Calls exclusively msw-perf (single
 * source of truth) -- via ctrl.perfCmd(), which wraps exec + refresh() in
 * main.qml (this file doesn't see `root`/`exec` from main.qml, hence the
 * detour via `ctrl`).
 *
 * Correlation highlight: a preset button only lights up when both the active
 * KDE profile (ctrl.perfProfile) AND the current cap (ctrl.maxPerfPct) match
 * the preset (band +/-8 %, see msw-perf band()). This way the button honestly
 * shows whether the actual state matches the preset -- not just which one was
 * last clicked.
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: performanceTab

    // Reference to the root PlasmoidItem from main.qml.
    property var ctrl

    spacing: Kirigami.Units.largeSpacing

    readonly property var presets: [
        { id: "power-saver", label: "Power saver", target: 40 },
        { id: "balanced",    label: "Balanced",    target: 70 },
        { id: "performance", label: "Performance", target: 100 }
    ]
    readonly property int bandTolerance: 8

    function inBand(target) {
        return Math.abs(ctrl.maxPerfPct - target) <= bandTolerance;
    }
    function isSelected(preset) {
        return ctrl.perfProfile === preset.id && inBand(preset.target);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: performanceTab.presets
            delegate: PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: modelData.label
                checked: performanceTab.isSelected(modelData)
                onClicked: ctrl.perfCmd(modelData.id)
            }
        }
    }

    // Fine CPU cap
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label { text: "CPU cap"; opacity: 0.7 }
        PlasmaComponents3.Slider {
            id: capSlider
            Layout.fillWidth: true
            from: 16
            to: 100
            stepSize: 1
            value: ctrl.maxPerfPct
            onPressedChanged: if (!pressed)
                ctrl.perfCmd("pct " + Math.round(value))
        }
        PlasmaComponents3.Label {
            text: Math.round(capSlider.value) + " %"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    PlasmaComponents3.Label {
        text: "Turbo: " + (ctrl.turbo ? "on" : "off") + "  ·  Profile: " + ctrl.perfProfile
        opacity: 0.7
        font: Kirigami.Theme.smallFont
    }

    Kirigami.Separator { Layout.fillWidth: true }

    /*
     * Devices & power: dGPU sleep, WiFi, Bluetooth, EPP. All via
     * ctrl.powerCmd() (msw-power) -- no bare root/exec access, same wrapping
     * as ctrl.perfCmd() above. ASPM and USB are deliberately left out (ASPM
     * unsupported by firmware on this class of device, USB not switchable).
     */
    PlasmaComponents3.Label {
        text: "Devices & Power"
        font.bold: true
    }

    // Local fallbacks until the first poll completes (ctrl.status.gpu/.power_extra
    // are undefined until then).
    readonly property var gpuState: (ctrl.status && ctrl.status.gpu) || ({ awake: false, watts: null, dstate: "?", control: "?" })
    readonly property var powerExtra: (ctrl.status && ctrl.status.power_extra) || ({ epp: "?", wifi: "?", bt: "?" })

    // dGPU
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label { text: "dGPU"; opacity: 0.7 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PlasmaComponents3.Label {
                text: performanceTab.gpuState.awake
                      ? "▲ " + (performanceTab.gpuState.watts !== null && performanceTab.gpuState.watts !== undefined
                                ? performanceTab.gpuState.watts + " W" : "active")
                        + " (" + performanceTab.gpuState.dstate + ")"
                      : "asleep (" + performanceTab.gpuState.dstate + ")"
            }
            // Show the management state explicitly (the button next to it is the ACTION)
            PlasmaComponents3.Label {
                text: "Management: " + (performanceTab.gpuState.control === "on" ? "kept awake"
                                        : performanceTab.gpuState.control === "auto" ? "sleep allowed (auto)"
                                        : "?")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }
        PlasmaComponents3.Button {
            // Label = what the click DOES (not the current state)
            text: performanceTab.gpuState.control === "on" ? "Allow sleep" : "Keep awake"
            icon.name: performanceTab.gpuState.control === "on" ? "system-suspend" : "dialog-ok"
            onClicked: ctrl.powerCmd(performanceTab.gpuState.control === "on" ? "gpu auto" : "gpu keep")
        }
    }

    // WiFi
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label { text: "WiFi"; opacity: 0.7 }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: performanceTab.powerExtra.wifi === "on" ? "on" : "off"
        }
        PlasmaComponents3.Button {
            text: performanceTab.powerExtra.wifi === "on" ? "off" : "on"
            onClicked: ctrl.powerCmd(performanceTab.powerExtra.wifi === "on" ? "wifi off" : "wifi on")
        }
    }

    // Bluetooth
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label { text: "Bluetooth"; opacity: 0.7 }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: performanceTab.powerExtra.bt === "on" ? "on" : "off"
        }
        PlasmaComponents3.Button {
            text: performanceTab.powerExtra.bt === "on" ? "off" : "on"
            onClicked: ctrl.powerCmd(performanceTab.powerExtra.bt === "on" ? "bt off" : "bt on")
        }
    }

    // EPP (energy bias)
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label { text: "Energy bias (EPP)"; opacity: 0.7 }
        PlasmaComponents3.ComboBox {
            id: eppCombo
            Layout.fillWidth: true
            model: ["default", "performance", "balance_performance", "balance_power", "power"]

            // Derive currentIndex ONLY from status (a function, not a direct
            // binding to onActivated) -- this avoids a binding loop: setting
            // currentIndex here does not trigger onActivated (that only fires
            // on user interaction), so powerCmd is not re-triggered on every
            // status refresh.
            function indexForEpp() {
                var idx = eppCombo.model.indexOf(performanceTab.powerExtra.epp);
                return idx >= 0 ? idx : 0;
            }
            currentIndex: indexForEpp()

            onActivated: {
                var picked = currentValue;
                if (picked !== performanceTab.powerExtra.epp)
                    ctrl.powerCmd("epp " + picked);
            }
        }
    }

    Item { Layout.fillHeight: true }
}
