/*
 * Mobile AI Server Switch — plasmoid for switching between server and laptop
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
    //
    // `export PATH=...;` (statement form, not the `VAR=val cmd` inline-prefix
    // form used previously) so the override applies to an entire command
    // *line* handed to `/bin/sh -c`, not just its first word -- required
    // since persistConfig() below runs a 3-stage pipeline
    // (printf | base64 | msw-config-write), and an inline `VAR=val` prefix
    // only scopes to the first simple command of a pipeline, not the rest of
    // it. configuration.binPath (General settings page) lets a user override
    // the auto-detected directory if it ever picks the wrong one; when unset
    // (default "") the auto chain ($HOME/.local/bin, then /usr/local/bin,
    // per the design doc) is used, unchanged from before this task.
    readonly property string pathPrefix: {
        var bp = Plasmoid.configuration.binPath;
        var dirs = (bp && bp.length > 0) ? [bp] : [];
        dirs.push("$HOME/.local/bin", "/usr/local/bin");
        return "export PATH=\"" + dirs.join(":") + ":$PATH\"; ";
    }

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
    property string perfProfile: (status.perf && status.perf.profile !== undefined
                                   && status.perf.profile !== null) ? status.perf.profile : "?"
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
    toolTipMainText: "Mobile AI Server Switch: " + modeLabel(mode)
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

    // --- Settings persistence (config.json writer) ----------------------------
    // The settings dialog (config/config.qml + ui/config*.qml) only edits
    // `plasmoid.configuration.*` flat KConfigXT keys -- QML has no direct
    // filesystem access, so the only way any of that reaches
    // ~/.config/mobileserverswitch/config.json (the file the CLIs actually
    // read) is through the "executable" DataSource, i.e. through
    // bin/msw-config-write, exactly like every other CLI invocation here.
    //
    // buildConfigJson() reassembles the nested shape config.json/the CLIs
    // expect (see config/config.example.json) from the flat keys. The three
    // *Json entries (servicesJson/stopOnLaptopJson/firewallAppsJson) are
    // themselves JSON-array strings (KConfigXT has no native list-of-object
    // type), parsed back into real arrays here.
    function buildConfigJson() {
        var c = Plasmoid.configuration;
        function parseArray(s) {
            try {
                var a = JSON.parse(s);
                return Array.isArray(a) ? a : [];
            } catch (e) {
                return [];
            }
        }
        return {
            network: {
                lan_interfaces: c.lanInterfaces,
                tailscale: c.tailscale,
                firewall_zone: c.firewallZone,
                wol_nic: c.wolNic
            },
            services: parseArray(c.servicesJson),
            mode: {
                enabled: c.modeEnabled,
                charge_thresholds: {
                    enabled: c.chargeThresholdsEnabled,
                    server: c.chargeServer,
                    laptop: c.chargeLaptop
                },
                stop_on_laptop: parseArray(c.stopOnLaptopJson)
            },
            firewall: {
                apps: parseArray(c.firewallAppsJson)
            },
            remote: {
                rdp: { enabled: c.rdpEnabled, bind: c.rdpBind }
            },
            features: {
                performance: c.showPerformance,
                mode: c.showMode,
                network: c.showNetwork,
                remote: c.showRemote,
                services: c.showServices,
                firewall: c.showFirewall
            }
        };
    }

    // btoa()/base64 round-trip (not a plain quoted string) so the JSON blob
    // can never break out of/corrupt the shell command line regardless of
    // its content (quotes, backslashes, newlines from multi-line labels,
    // etc.) -- base64's alphabet (A-Za-z0-9+/=) is entirely shell-safe even
    // inside single quotes. Qt.btoa() alone only handles Latin1 (like
    // browser btoa()); encodeURIComponent+unescape first re-packs the JSON
    // string's UTF-8 bytes into that Latin1-range "binary string" so
    // non-ASCII service labels/ids survive intact.
    function persistConfig() {
        var json = JSON.stringify(root.buildConfigJson());
        var b64 = Qt.btoa(unescape(encodeURIComponent(json)));
        exec.run("printf '%s' '" + b64 + "' | base64 -d | msw-config-write",
            function(out, err, code) {
                if (code !== 0)
                    console.warn("msw-config-write failed (exit " + code + "):", err || out);
            });
    }

    // Coalesces a whole Apply/OK click (which can change several
    // Plasmoid.configuration keys at once, each firing its own onXChanged
    // below) into a single msw-config-write invocation instead of one per
    // changed key.
    Timer {
        id: persistDebounce
        interval: 50
        repeat: false
        onTriggered: root.persistConfig()
    }
    function requestPersist() { persistDebounce.restart(); }

    // Plasmoid.configuration.* only updates on Apply/OK (the config dialog
    // edits its own `cfg_*` working copies until then), so one
    // requestPersist() call per relevant key here means one write per saved
    // change, not per keystroke. `binPath` is deliberately NOT listed: it is
    // plasmoid-only (CLI tool resolution, see pathPrefix above), never part
    // of config.json. Per-property notify-signal convention
    // (`on<PascalCaseName>Changed`) verified against
    // org.kde.desktopcontainment/ui/FolderViewLayer.qml and FolderView.qml,
    // which both wire `Connections { target: Plasmoid.configuration;
    // function on<Name>Changed() {...} }` the same way.
    Connections {
        target: Plasmoid.configuration
        function onLanInterfacesChanged() { root.requestPersist(); }
        function onTailscaleChanged() { root.requestPersist(); }
        function onFirewallZoneChanged() { root.requestPersist(); }
        function onWolNicChanged() { root.requestPersist(); }
        function onServicesJsonChanged() { root.requestPersist(); }
        function onModeEnabledChanged() { root.requestPersist(); }
        function onChargeThresholdsEnabledChanged() { root.requestPersist(); }
        function onChargeServerChanged() { root.requestPersist(); }
        function onChargeLaptopChanged() { root.requestPersist(); }
        function onStopOnLaptopJsonChanged() { root.requestPersist(); }
        function onFirewallAppsJsonChanged() { root.requestPersist(); }
        function onRdpEnabledChanged() { root.requestPersist(); }
        function onRdpBindChanged() { root.requestPersist(); }
        function onShowPerformanceChanged() { root.requestPersist(); }
        function onShowModeChanged() { root.requestPersist(); }
        function onShowNetworkChanged() { root.requestPersist(); }
        function onShowRemoteChanged() { root.requestPersist(); }
        function onShowServicesChanged() { root.requestPersist(); }
        function onShowFirewallChanged() { root.requestPersist(); }
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
    // Tabbed: Overview | Performance | Mode | Network | Remote Access | Services | Firewall.
    // Overview is the default tab (currentIndex: 0), so the popup always opens there.
    // Every tab gets access to this PlasmoidItem's state/functions via ctrl:root
    // -- separate .qml files don't otherwise see `root`/`exec` (no global
    // scope). OverviewTab also can't see `tabs` (lives here in the
    // fullRepresentation scope), so it passes clicks up through the
    // navigate(key) signal instead, resolved against visibleTabs below via
    // indexOfTab().
    //
    // Visible tabs are config-driven (General settings page's "Visible tabs"
    // checkboxes -> Plasmoid.configuration.show<Key>, default true -- see
    // config/main.xml). `visibleTabs` below is the SINGLE shared model both
    // the TabBar and the StackLayout are rendered from via Repeater, so
    // index parity between them is automatic: a hidden tab is truly absent
    // from both (no dead control, no blank-gap/StackLayout-visible-clobber
    // issues like Task 5's hide-the-TabButton-only approach had). Overview
    // is `always: true` -- there is no showOverview checkbox, it can't be
    // hidden. Firewall stays in the model even when firewalld is absent;
    // FirewallTab.qml already shows its own "requires firewalld" message
    // internally for that case, so the tab is only hidden by its own
    // checkbox, same as any other tab.
    fullRepresentation: ColumnLayout {
        id: fullRep
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        spacing: Kirigami.Units.smallSpacing

        // Each entry directly reads its Plasmoid.configuration.show<X> flag
        // (not via bracket-notation indirection) so QML's binding dependency
        // tracking picks it up correctly: this property re-evaluates
        // whenever any show* config key changes (e.g. after Apply/OK on the
        // General settings page).
        readonly property var allTabsData: [
            { key: "overview", label: "Overview", always: true },
            { key: "performance", label: "Performance", always: false, show: Plasmoid.configuration.showPerformance },
            { key: "mode", label: "Mode", always: false, show: Plasmoid.configuration.showMode },
            { key: "network", label: "Network", always: false, show: Plasmoid.configuration.showNetwork },
            { key: "remote", label: "Remote Access", always: false, show: Plasmoid.configuration.showRemote },
            { key: "services", label: "Services", always: false, show: Plasmoid.configuration.showServices },
            { key: "firewall", label: "Firewall", always: false, show: Plasmoid.configuration.showFirewall }
        ]

        // The filtered model: recomputed automatically whenever allTabsData
        // changes (see above). `show !== false` so an unset/undefined flag
        // defaults to visible, matching main.xml's <default>true</default>.
        readonly property var visibleTabs: allTabsData.filter(function(t) {
            return t.always || t.show !== false;
        })

        // Maps a tab's `key` to its content Component. Kept out of
        // allTabsData/visibleTabs (which stay plain, comparable data used
        // for dependency tracking / filtering) and looked up here instead.
        function componentForKey(key) {
            switch (key) {
            case "overview": return overviewComp;
            case "performance": return performanceComp;
            case "mode": return modeComp;
            case "network": return networkComp;
            case "remote": return remoteComp;
            case "services": return servicesComp;
            case "firewall": return firewallComp;
            }
            return null;
        }

        // Resolves a navigation key (from OverviewTab's navigate signal)
        // against the *visible* tabs, so a hidden tab can never misdirect a
        // click onto whatever happens to sit at that position. Looks the key
        // up by value rather than hard-coding the current key set, so future
        // tabs need no changes here. Returns -1 if the key isn't visible
        // (e.g. its own tab is hidden) -- the caller must treat that as "do
        // nothing", not as index 0.
        function indexOfTab(key) {
            for (var i = 0; i < visibleTabs.length; i++)
                if (visibleTabs[i].key === key) return i;
            return -1;
        }

        // One Component per tab, each with `ctrl: root` set inline (so the
        // Loader below never needs an onLoaded/item.ctrl-assignment step --
        // the property is already bound at instantiation time).
        Component {
            id: overviewComp
            OverviewTab {
                ctrl: root
                onNavigate: (key) => {
                    var i = fullRep.indexOfTab(key);
                    if (i >= 0) tabs.currentIndex = i;
                }
            }
        }
        Component { id: performanceComp; PerformanceTab { ctrl: root } }
        Component { id: modeComp; ModeTab { ctrl: root } }
        Component { id: networkComp; NetworkTab { ctrl: root } }
        Component { id: remoteComp; RemoteAccessTab { ctrl: root } }
        Component { id: servicesComp; ServicesTab { ctrl: root } }
        Component { id: firewallComp; FirewallTab { ctrl: root } }

        PlasmaComponents3.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: 0
            Repeater {
                model: fullRep.visibleTabs
                delegate: PlasmaComponents3.TabButton { text: modelData.label }
            }
        }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            Repeater {
                model: fullRep.visibleTabs
                delegate: Loader {
                    sourceComponent: fullRep.componentForKey(modelData.key)
                }
            }
        }
    }
}
