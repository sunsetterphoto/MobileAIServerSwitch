/*
 * "Mode" tab -- generic profile switcher (formerly hardcoded server/laptop
 * with a Sunshine-specific confirmation).
 *
 * The active profile and the list of available profiles come from
 * `msw-status --json` (status.profiles.active / status.profiles.available).
 * Before the first poll -- or with an older CLI that has no profiles block
 * -- the list falls back to the locally configured profiles
 * (ctrl.profilesMap, parsed from the profilesJson setting), so the tab is
 * never empty.
 *
 * Safety feature (generalizes the old "switching to laptop stops Sunshine"
 * rule): if the TARGET profile's services.stop list names services that are
 * currently RUNNING (per status.services), switching would kill a running
 * stream/session -- only then does the switch ask for confirmation. Every
 * other switch is immediate.
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

    // Profile awaiting confirmation: {id, label, stops:[running labels]} or null.
    property var pendingProfile: null

    // Available profiles: prefer live data from msw-status (it knows custom
    // profiles and the builtin flag); fall back to the configured profiles
    // map. Each entry is normalized to at least {id, label, icon}.
    readonly property var profileList: {
        var p = ctrl.status ? ctrl.status.profiles : null;
        if (p && Array.isArray(p.available) && p.available.length > 0)
            return p.available;
        var m = ctrl.profilesMap || {};
        var out = [];
        for (var k in m) {
            if (!m[k] || typeof m[k] !== "object") continue;
            out.push({ id: k, label: m[k].label || k,
                       icon: m[k].icon || "dialog-question" });
        }
        return out;
    }

    // services.stop entries of a profile. The full definition is NOT part of
    // status.profiles.available -- it comes from the configured profiles map.
    function stopEntries(profileId) {
        var p = (ctrl.profilesMap || {})[profileId];
        if (!p || !p.services || !Array.isArray(p.services.stop)) return [];
        return p.services.stop;
    }

    // Labels of stop-listed services that are currently RUNNING. A stop
    // entry may be a service id OR a unit name (CLI contract) -- match both
    // against the configured services. ctrl.servicesList tolerates both
    // msw-status shapes (flat array / {configured, detected}). Entries that
    // match no known service can't be checked and never trigger a prompt.
    function runningStops(profileId) {
        var stops = stopEntries(profileId);
        var running = [];
        var svcs = ctrl.servicesList || [];
        for (var i = 0; i < stops.length; i++) {
            for (var j = 0; j < svcs.length; j++) {
                var s = svcs[j];
                if (s && (s.id === stops[i] || s.unit === stops[i]) && s.active === true) {
                    running.push(s.label || stops[i]);
                    break;
                }
            }
        }
        return running;
    }

    function requestSwitch(profile) {
        if (ctrl.busy || !profile || !profile.id) return;
        if (profile.id === ctrl.mode) return;   // already active
        var running = runningStops(profile.id);
        if (running.length > 0)
            pendingProfile = { id: profile.id, label: profile.label || profile.id,
                               stops: running };
        else
            ctrl.switchMode(profile.id);
    }

    spacing: Kirigami.Units.smallSpacing

    // Header: active profile
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
                text: "Active profile"
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

        PlasmaComponents3.Label { text: "Charge thresholds:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: ctrl.charge }
        PlasmaComponents3.Label { text: "Battery:"; opacity: 0.7 }
        PlasmaComponents3.Label { text: ctrl.battery >= 0 ? ctrl.battery + " %" : "?" }
    }

    Item { Layout.fillHeight: true }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: ctrl.busy
        text: "Switching profile …"
        opacity: 0.7
    }

    // Confirmation (only when the target profile would stop running services)
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: modeTab.pendingProfile !== null
        wrapMode: Text.WordWrap
        text: modeTab.pendingProfile
              ? "Switching to '" + modeTab.pendingProfile.label
                + "' will stop running services: "
                + modeTab.pendingProfile.stops.join(", ") + ". Continue?"
              : ""
        color: Kirigami.Theme.neutralTextColor
    }
    RowLayout {
        Layout.fillWidth: true
        visible: modeTab.pendingProfile !== null
        PlasmaComponents3.Button {
            Layout.fillWidth: true
            icon.name: "dialog-ok"
            text: modeTab.pendingProfile ? "Yes, switch to " + modeTab.pendingProfile.label
                                         : "Yes"
            enabled: !ctrl.busy
            onClicked: {
                var target = modeTab.pendingProfile;
                modeTab.pendingProfile = null;
                if (target) ctrl.switchMode(target.id);
            }
        }
        PlasmaComponents3.Button {
            Layout.fillWidth: true
            icon.name: "dialog-cancel"
            text: "Cancel"
            onClicked: modeTab.pendingProfile = null
        }
    }

    // Profile list: one button per profile; the active one is non-flat and
    // carries a check emblem. Disabled while a switch is in flight.
    Repeater {
        model: modeTab.profileList
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Button {
                Layout.fillWidth: true
                icon.name: modelData.icon || "dialog-question"
                text: modelData.label || modelData.id
                flat: modelData.id !== modeTab.ctrl.mode
                enabled: !modeTab.ctrl.busy
                onClicked: modeTab.requestSwitch(modelData)
            }
            Kirigami.Icon {
                source: "emblem-checked"
                visible: modelData.id === modeTab.ctrl.mode
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: modeTab.profileList.length === 0
        text: "No profiles available -- define some on the Profiles settings page."
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    PlasmaComponents3.Button {
        Layout.fillWidth: true
        flat: true
        icon.name: "view-refresh"
        text: "Refresh"
        onClicked: ctrl.refresh()
    }
}
