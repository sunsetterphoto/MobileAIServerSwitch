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

    // Presets need PowerProfiles (org.freedesktop.UPower.PowerProfiles) to
    // apply a profile; msw-status reports perf.profile "?" when that D-Bus
    // service isn't available. The fine cap has no equivalent readable
    // signal of its own (msw-status silently falls back to a plausible
    // default when intel_pstate's max_perf_pct can't be read) -- so per the
    // task brief it is gated on the same perf.profile signal.
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: ctrl.perfProfile !== "?"
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
        visible: ctrl.perfProfile !== "?"
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
     * Devices & power: dGPU sleep, WiFi, Bluetooth. All via ctrl.powerCmd()
     * (msw-power) -- no bare root/exec access, same wrapping as ctrl.perfCmd()
     * above. ASPM and USB are deliberately left out (ASPM unsupported by
     * firmware on this class of device, USB not switchable), and EPP was
     * removed from the UI (see the note further down).
     */
    PlasmaComponents3.Label {
        text: "Devices & Power"
        font.bold: true
    }

    // Local fallbacks until the first poll completes (ctrl.status.gpu/.power_extra
    // are undefined until then).
    readonly property var gpuState: (ctrl.status && ctrl.status.gpu) || ({ present: false, awake: false, watts: null, dstate: "?", control: "?" })
    readonly property var powerExtra: (ctrl.status && ctrl.status.power_extra) || ({ wifi: "?", bt: "?" })

    // dGPU -- hidden entirely when there's no discrete GPU on this system
    // (msw-status gpu.present, PCI device 0000:01:00.0 absent).
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: performanceTab.gpuState.present === true
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

    // WiFi -- hidden when the value is absent/"?" (e.g. no rfkill wifi radio).
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: performanceTab.powerExtra.wifi === "on" || performanceTab.powerExtra.wifi === "off"
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

    // Bluetooth -- hidden when the value is absent/"?" (e.g. no rfkill bt radio).
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: performanceTab.powerExtra.bt === "on" || performanceTab.powerExtra.bt === "off"
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

    // The Energy Performance Preference (EPP) selector used to sit here. It was
    // removed: its picker kept snapping back to the value the last status poll
    // reported, and EPP is the weakest of these controls anyway -- the preset
    // and the CPU cap decide the machine's behaviour, EPP only biases how
    // eagerly the CPU ramps between them. `msw-power epp <pref>` still exists
    // for anyone who wants it from a shell; it was the widget control that was
    // not worth its own bug.

    Item { Layout.fillHeight: true }
}
