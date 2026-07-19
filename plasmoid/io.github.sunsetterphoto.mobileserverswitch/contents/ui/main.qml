/*
 * Mobile Server Switch — plasmoid for switching between server and laptop
 * operation, plus a status/control center for performance, power, remote
 * access, services and firewall.
 *
 * Calls exclusively the `msw-*` CLIs (single source of truth). NOTHING of the
 * logic is duplicated here — the plasmoid is pure GUI.
 *
 * Security feature: switching to LAPTOP stops Sunshine and the server
 * services. That is why exactly this switch requires confirmation, so a
 * mis-click can't kill a running stream. Switching to SERVER is immediate.
 *
 * API verified against Plasma 6.7:
 *   - PlasmoidItem, compact/fullRepresentation  (org.kde.plasma.plasmoid)
 *   - Plasma5Support.DataSource engine "executable" with connectSource/newData
 *
 * Tool resolution: the "executable" engine runs each command via `/bin/sh -c`,
 * and `~/.local/bin` is not guaranteed to be on PATH in that shell (depends on
 * the display manager / session setup). Rather than hardcoding an absolute
 * `/home/<user>/...` path (which would break for every other user), each
 * command is prefixed with `PATH="$HOME/.local/bin:$PATH"` — `/bin/sh -c`
 * expands `$HOME` for us at run time, so this resolves correctly for whoever
 * is running the session without baking in any specific username or path.
 */
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Prefix so the CLIs are found regardless of the shell's PATH (see file
    // header comment). Every exec.run() call below wraps its command in this.
    readonly property string pathPrefix: "PATH=\"$HOME/.local/bin:$PATH\" "

    readonly property string tool: "msw-mode"
    readonly property string statusTool: "msw-status"
    readonly property string perfTool: "msw-perf"
    readonly property string powerTool: "msw-power"
    readonly property string firewallTool: "msw-firewall"

    // --- State, read from msw-status --json ----------------------------------
    property var status: ({})          // last successfully parsed overall object
    property bool busy: false          // is a mode switch currently running?

    // Derived properties: existing UI bindings stay unchanged, defaults apply
    // until the first poll completes (status === {}).
    property string mode: status.mode || "?"           // "server" | "laptop" | "?"
    property string sunshine: {                        // "active" | "inactive" | "?"
        if (!status.remote || !status.remote.sunshine) return "?";
        return status.remote.sunshine.active ? "active" : "inactive";
    }
    property string charge: (status.power && status.power.charge !== undefined
                              && status.power.charge !== null) ? status.power.charge : "?"
    property int battery: (status.power && status.power.battery !== undefined
                            && status.power.battery !== null) ? status.power.battery : -1

    // Performance axis: feeds PerformanceTab (presets/slider/turbo display).
    property string perfProfile: (status.perf && status.perf.profile) ? status.perf.profile : "?"
    property int maxPerfPct: (status.perf && status.perf.max_perf_pct !== undefined
                               && status.perf.max_perf_pct !== null) ? status.perf.max_perf_pct : 100
    property bool turbo: (status.perf && status.perf.turbo !== undefined) ? status.perf.turbo : true

    readonly property bool isServer: mode === "server"
    readonly property bool isLaptop: mode === "laptop"

    function modeLabel(m) {
        if (m === "server") return "Server (always on)";
        if (m === "laptop") return "Laptop (mobile)";
        return "unknown";
    }
    function modeIcon(m) {
        if (m === "server") return "network-server";
        if (m === "laptop") return "computer-laptop";
        return "dialog-question";
    }

    Plasmoid.icon: modeIcon(mode)
    toolTipMainText: "Mobile Server Switch: " + modeLabel(mode)
    // Compact tooltip = the "at a glance" area in the panel (hover, no click).
    // Summarizes the most important bits from msw-status; every access to
    // status.* is guarded against the pre-poll state ({}).
    toolTipSubText: {
        var s = "Performance: " + perfProfile + " · " + maxPerfPct + "%"
                + (turbo ? "" : " (turbo off)");
        s += "\nSunshine: " + sunshine;
        if (status.gpu)
            s += "\ndGPU: " + (status.gpu.awake
                ? ((status.gpu.watts !== null && status.gpu.watts !== undefined)
                   ? status.gpu.watts + " W" : "active")
                : "asleep");
        if (battery >= 0)
            s += "\nBattery: " + battery + "%"
                 + (status.power && status.power.ac !== undefined
                    ? " (" + (status.power.ac ? "AC" : "battery") + ")" : "");
        s += "\nCharge thresholds: " + charge;
        // Show active LAN blocks (firewall) only when any are set.
        if (status.firewall && status.firewall.apps) {
            var blocked = [];
            for (var k in status.firewall.apps)
                if (status.firewall.apps[k] && status.firewall.apps[k].blocked)
                    blocked.push(k);
            if (blocked.length > 0)
                s += "\nLAN blocked: " + blocked.join(", ");
        }
        return s;
    }

    // Without preferredRepresentation the shell decides by form factor:
    // panel -> compact (click opens popup), desktop -> full view.

    // --- Command execution -----------------------------------------------------
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        // Callbacks per source command; disconnected again after the reply.
        property var callbacks: ({})

        onNewData: (source, data) => {
            var cb = callbacks[source];
            if (cb) {
                cb(data["stdout"] || "", data["stderr"] || "", data["exit code"]);
                delete callbacks[source];
            }
            disconnectSource(source);
        }
        function run(cmd, cb) {
            var full = root.pathPrefix + cmd;
            if (cb)
                callbacks[full] = cb;
            connectSource(full);
        }
    }

    function refresh() {
        exec.run(statusTool + " --json", function(out) {
            try {
                root.status = JSON.parse(out);
            } catch (e) {
                console.warn("msw-status JSON parse error:", e, "output:", out);
                // status stays at its last valid value.
            }
        });
    }

    function switchMode(target) {
        if (busy) return;
        root.busy = true;
        exec.run(tool + " " + target, function(out, err, code) {
            root.busy = false;
            refresh();
        });
    }

    // Performance commands (msw-perf): presets and fine CPU cap. No dedicated
    // busy guard needed -- msw-perf is uncritical (no Sunshine stop), so it is
    // usable without confirmation and without a busy lock.
    function perfCmd(args) {
        exec.run(perfTool + " " + args, function() { refresh(); });
    }

    // Device/power commands (msw-power): dGPU runtime PM, WiFi, Bluetooth, EPP.
    // Same as perfCmd, uncritical (no Sunshine stop), so usable without
    // confirmation and without a busy lock. Uses the same runAndRefresh mechanism.
    function powerCmd(args) {
        runAndRefresh(powerTool + " " + args);
    }

    // Firewall commands (msw-firewall): set/clear the per-app LAN block.
    // Same as powerCmd uncritical for the widget (LAN zone only, never
    // ssh/tailnet -- the privileged helper enforces that), so no busy lock.
    // Via runAndRefresh.
    function firewallCmd(args) {
        runAndRefresh(firewallTool + " " + args);
    }

    // Generic helper for tabs that need to run arbitrary shell commands (e.g.
    // ServicesTab: systemctl start/stop). exec + refresh live in root scope,
    // tabs don't see them directly -- hence via ctrl.runAndRefresh.
    function runAndRefresh(cmd) {
        exec.run(cmd, function(){ refresh(); });
    }

    Component.onCompleted: refresh()

    // Refresh periodically so the displayed mode stays correct even when it
    // was switched via SSH/CLI (msw-mode ...).
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // --- Compact representation (panel): icon, click opens popup ------------
    compactRepresentation: MouseArea {
        id: compact
        activeFocusOnTab: true
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: root.modeIcon(root.mode)
            active: compact.containsMouse
            // Light status dot: green = server, blue = laptop
            Rectangle {
                width: Math.round(parent.width * 0.30)
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root.mode === "server" || root.mode === "laptop"
                color: root.isServer ? Kirigami.Theme.positiveTextColor
                                     : Kirigami.Theme.highlightColor
                border.width: 1
                border.color: Kirigami.Theme.backgroundColor
            }
        }
    }

    // --- Full representation (popup / desktop) -------------------------------
    // Tabbed: Overview | Performance | Mode | Remote Access | Services | Firewall.
    // Overview is the default tab (currentIndex: 0), so the popup always opens there.
    // Every tab gets access to this PlasmoidItem's state/functions via ctrl:root
    // -- separate .qml files don't otherwise see `root`/`exec` (no global
    // scope). OverviewTab also can't see `tabs` (lives here in the
    // fullRepresentation scope), so it passes clicks up through the
    // navigate(index) signal instead.
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: 0
            PlasmaComponents3.TabButton { text: "Overview" }
            PlasmaComponents3.TabButton { text: "Performance" }
            PlasmaComponents3.TabButton { text: "Mode" }
            PlasmaComponents3.TabButton { text: "Remote Access" }
            PlasmaComponents3.TabButton { text: "Services" }
            PlasmaComponents3.TabButton { text: "Firewall" }
        }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            OverviewTab { ctrl: root; onNavigate: (i) => tabs.currentIndex = i }
            PerformanceTab { ctrl: root }
            ModeTab { ctrl: root }
            RemoteAccessTab { ctrl: root }
            ServicesTab { ctrl: root }
            FirewallTab { ctrl: root }
        }
    }
}
