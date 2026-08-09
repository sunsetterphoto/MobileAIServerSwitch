/*
 * Mobile AI Server Switch — plasmoid for switching between operation
 * PROFILES (builtin: server/laptop; custom profiles are defined on the
 * Profiles settings page), plus a status/control center for performance,
 * power, remote access, services and firewall.
 *
 * Calls exclusively the `msw-*` CLIs (single source of truth). NOTHING of the
 * logic is duplicated here — the plasmoid is pure GUI.
 *
 * Security feature: if the TARGET profile's services.stop list names
 * services that are currently running, switching to it asks for
 * confirmation first, so a mis-click can't kill a running stream. Every
 * other switch is immediate. (Generalizes the former hardcoded "switching
 * to laptop stops Sunshine" rule; the check lives in ModeTab.qml.)
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
    readonly property string notesTool: "msw-notes"

    // --- State, read from msw-status --json ----------------------------------
    property var status: ({})          // last successfully parsed overall object
    property bool busy: false          // is a mode switch currently running?

    // Derived properties: existing UI bindings stay unchanged, defaults apply
    // until the first poll completes (status === {}).
    // Active profile id ("server" | "laptop" | <custom id> | "?"). Newer
    // CLIs report it in status.profiles.active; status.mode is the legacy
    // location, kept as fallback for CLIs without a profiles block.
    property string mode: {
        if (status.profiles && typeof status.profiles.active === "string"
                && status.profiles.active.length > 0)
            return status.profiles.active;
        return status.mode || "?";
    }
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

    // Parsed profilesJson setting (configured profile definitions, keyed by
    // id). Feeds ModeTab's stop-confirmation logic and serves as label/icon
    // fallback below. Re-evaluates automatically on every profilesJson
    // change; parse failures degrade to {} (never throw into the UI).
    property var profilesMap: {
        try {
            var o = JSON.parse(Plasmoid.configuration.profilesJson);
            return (o && typeof o === "object" && !Array.isArray(o)) ? o : {};
        } catch (e) {
            return {};
        }
    }

    // Configured services from msw-status, tolerant of both shapes: the
    // legacy flat array and the newer object with "configured"/"detected"
    // arrays (the latter additionally lists installed-but-unconfigured
    // units). ModeTab checks this to decide whether a profile switch would
    // stop a running service.
    readonly property var servicesList: {
        var s = status.services;
        if (Array.isArray(s)) return s;
        if (s && Array.isArray(s.configured)) return s.configured;
        return [];
    }

    // Look a profile id up in the live list from msw-status (carries
    // label/icon/builtin for custom profiles too).
    function profileEntry(m) {
        var avail = (status.profiles && status.profiles.available) || [];
        for (var i = 0; i < avail.length; i++)
            if (avail[i] && avail[i].id === m) return avail[i];
        return null;
    }
    // Label/icon resolution order: status.profiles.available -> configured
    // profilesMap -> legacy hardcoded builtin texts (CLIs without a
    // profiles block) -> the raw id / generic icon.
    function modeLabel(m) {
        var e = profileEntry(m);
        if (e && e.label) return e.label;
        var p = profilesMap[m];
        if (p && p.label) return p.label;
        if (m === "server") return "Server (always on)";
        if (m === "laptop") return "Laptop (mobile)";
        if (m === "?") return "unknown";
        return m;
    }
    function modeIcon(m) {
        var e = profileEntry(m);
        if (e && e.icon) return e.icon;
        var p = profilesMap[m];
        if (p && p.icon) return p.icon;
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
        // Disambiguates concurrent calls (see run() below).
        property int seq: 0

        onNewData: (source, data) => {
            var cb = callbacks[source];
            if (cb) {
                cb(data["stdout"] || "", data["stderr"] || "", data["exit code"]);
                delete callbacks[source];
            }
            disconnectSource(source);
        }
        // The engine keys/deduplicates sources by their literal command
        // string, and callbacks[] above does the same -- so two concurrent
        // run() calls for the SAME argument-less command (e.g. "msw-notes
        // mtime", issued from more than one place in NotesTab.qml within a
        // short window) would collide: the second connectSource() call
        // overwrites the first callback before its reply arrives, and the
        // engine drops the duplicate source. Appending a trailing shell
        // comment with an incrementing counter makes every invocation's
        // source string unique -- it changes nothing about what actually
        // runs (a "# N" comment is inert to /bin/sh) -- so no two in-flight
        // calls can ever collide, no matter how many callers overlap.
        function run(cmd, cb) {
            exec.seq++;
            var full = root.pathPrefix + cmd + "  # " + exec.seq;
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

    // Notes are user data, not machine state: they are deliberately NOT part
    // of msw-status (that JSON gets handed around and will be served over an
    // API), and the 5 s poll would fight the user's typing. Loaded on demand.
    //
    // `msw-notes read` exits non-zero (and prints nothing to stdout) when the
    // file EXISTS but could not be read -- a permission problem, or a
    // directory at the notes path -- as opposed to exit 0 with empty stdout
    // for a genuinely missing file. The two must never be conflated: treating
    // "unreadable" as "empty" is exactly the bug this distinction exists to
    // prevent (see NotesTab.qml's loadFailed handling). On success (exit 0,
    // whether content or genuinely missing) `read` also prints
    // "MTIME:<epoch>" to stderr, read in that SAME invocation immediately
    // before the content -- cb's mtime therefore never comes from a second,
    // separate round trip that could itself race an external writer. cb
    // receives (text, code, mtimeOrMinus1).
    function notesLoad(cb) {
        exec.run(notesTool + " read", function(out, err, code) {
            if (code !== 0) { cb("", code, -1); return; }
            var m = /MTIME:(\d+)/.exec(err);
            cb(out, code, m ? parseInt(m[1], 10) : -1);
        });
    }
    function notesMtime(cb) {
        exec.run(notesTool + " mtime", function(out, err, code) {
            cb(code === 0 ? parseInt(out.trim(), 10) || 0 : -1);
        });
    }
    // msw-notes write prints the mtime it just set (part of the SAME
    // invocation that wrote the file) so the caller can adopt it directly
    // instead of issuing a second, separate "mtime" call afterwards -- a
    // second call would leave a window in which an external writer could
    // land and get silently mistaken for our own write. cb receives
    // (exitCode, mtimeOrMinus1).
    function notesSave(text, cb) {
        var b64 = Qt.btoa(unescape(encodeURIComponent(text)));
        exec.run(notesTool + " write --base64 '" + b64 + "'", function(out, err, code) {
            cb(code, code === 0 ? (parseInt(out.trim(), 10) || 0) : -1);
        });
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
    // expect (see config/config.example.json) from the flat keys. The
    // *Json entries (servicesJson/stopOnLaptopJson/firewallAppsJson) are
    // themselves JSON-array strings and profilesJson a JSON-object string
    // (KConfigXT has no native list/map-of-object types), parsed back into
    // real arrays/objects here.
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
        function parseObject(s) {
            try {
                var o = JSON.parse(s);
                return (o && typeof o === "object" && !Array.isArray(o)) ? o : {};
            } catch (e) {
                return {};
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
            // Whole "profiles" map (replaces the legacy per-mode keys below
            // on the CLI side; msw-config-write is called with
            // `--replace profiles` so deletions propagate).
            profiles: parseObject(c.profilesJson),
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
                firewall: c.showFirewall,
                notes: c.showNotes
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
        // `--replace profiles`: everything else deep-merges as before, but
        // the "profiles" key is replaced wholesale so profile DELETIONS
        // from the Profiles settings page propagate to config.json.
        exec.run("printf '%s' '" + b64 + "' | base64 -d | msw-config-write --replace profiles",
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
        function onProfilesJsonChanged() { root.requestPersist(); }
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
        function onShowNotesChanged() { root.requestPersist(); }
    }

    // --- One-time migration: legacy Mode keys -> profiles -------------------
    // Before the generic profiles rework, per-mode settings lived in the
    // flat legacy keys chargeThresholdsEnabled/chargeServer/chargeLaptop/
    // stopOnLaptopJson (they intentionally remain in main.xml as the
    // migration source; no settings page edits them anymore). Those values
    // now live inside profiles.<id>. This runs ONCE at load: only when
    // profilesJson is still the untouched kcfg default AND at least one
    // legacy key deviates from ITS default (i.e. the user actually
    // configured something under the old scheme). The merged result is
    // written back to profilesJson, which triggers persistConfig() via
    // onProfilesJsonChanged, so the migrated profiles reach config.json
    // immediately.
    //
    // MUST stay in sync with the profilesJson <default> in
    // contents/config/main.xml (and configProfiles.qml's
    // cfg_profilesJsonDefault).
    readonly property string profilesDefaultJson: '{"server":{"label":"Server","icon":"network-server","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"ignore","power_button":"ignore","power_button_long":"ignore","auto_suspend":"ignore","auto_suspend_min":0,"screen_off_min":0,"dim_min":0,"wol":"on"},"locker":{"autolock":true,"timeout_min":15},"charge_thresholds":"40/80","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":["sunshine"],"stop":[]},"radios":{"wifi":"keep","bluetooth":"keep"}},"laptop":{"label":"Laptop","icon":"computer-laptop","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"sleep","power_button":"prompt","power_button_long":"shutdown","auto_suspend":"sleep","auto_suspend_min":30,"screen_off_min":10,"dim_min":5,"wol":"off"},"locker":{"autolock":true,"timeout_min":5},"charge_thresholds":"0/100","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":[],"stop":["sunshine"]},"radios":{"wifi":"on","bluetooth":"keep"}}}'

    function defaultProfiles() {
        try {
            return JSON.parse(profilesDefaultJson);
        } catch (e) {
            return {};
        }
    }

    // "Still the default?" -- exact string match first, then a semantic
    // comparison (parse + re-serialize) so harmless formatting differences
    // don't defeat the check. A user-customized map never matches.
    function isDefaultProfilesJson(s) {
        if (s === profilesDefaultJson) return true;
        try {
            return JSON.stringify(JSON.parse(s)) === JSON.stringify(defaultProfiles());
        } catch (e) {
            return false;
        }
    }

    function migrateLegacyProfileSettings() {
        var c = Plasmoid.configuration;
        if (!isDefaultProfilesJson(c.profilesJson)) return;
        // Legacy defaults from main.xml (keep in sync if they ever change):
        var legacyTouched =
            c.chargeThresholdsEnabled !== false ||
            c.chargeServer !== "40/80" ||
            c.chargeLaptop !== "0/100" ||
            c.stopOnLaptopJson !== "[]";
        if (!legacyTouched) return;
        var profiles = defaultProfiles();
        if (!profiles.server || !profiles.laptop) return;  // broken default: do nothing
        // Charge thresholds: under the old scheme "disabled" meant "don't
        // touch" -> null in the profile schema. Enabled -> per-mode values.
        if (c.chargeThresholdsEnabled) {
            profiles.server.charge_thresholds = c.chargeServer;
            profiles.laptop.charge_thresholds = c.chargeLaptop;
        } else {
            profiles.server.charge_thresholds = null;
            profiles.laptop.charge_thresholds = null;
        }
        // stop_on_laptop ids: the server profile STARTS them, the laptop
        // profile STOPS them. Union with the builtin defaults so "sunshine"
        // is kept even when the legacy list named only other services.
        var stops = [];
        try {
            var a = JSON.parse(c.stopOnLaptopJson);
            if (Array.isArray(a)) stops = a;
        } catch (e) { /* keep [] */ }
        function union(list, add) {
            var out = list.slice();
            for (var i = 0; i < add.length; i++)
                if (out.indexOf(add[i]) < 0) out.push(add[i]);
            return out;
        }
        profiles.server.services.start = union(profiles.server.services.start, stops);
        profiles.laptop.services.stop = union(profiles.laptop.services.stop, stops);
        Plasmoid.configuration.profilesJson = JSON.stringify(profiles);
    }

    Component.onCompleted: {
        refresh();
        migrateLegacyProfileSettings();
    }

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
            // Light status dot: green = server, blue = laptop, grey = any
            // other (custom) profile; hidden while the mode is unknown.
            Rectangle {
                width: Math.round(parent.width * 0.30)
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root.mode !== "?"
                color: root.isServer ? Kirigami.Theme.positiveTextColor
                       : root.isLaptop ? Kirigami.Theme.highlightColor
                       : Kirigami.Theme.neutralTextColor
                border.width: 1
                border.color: Kirigami.Theme.backgroundColor
            }
        }
    }

    // --- Full representation (popup / desktop) -------------------------------
    // Tabbed: Overview | Performance | Mode | Network | Remote Access | Services | Firewall | Notes.
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
            { key: "firewall", label: "Firewall", always: false, show: Plasmoid.configuration.showFirewall },
            { key: "notes", label: "Notes", always: false, show: Plasmoid.configuration.showNotes }
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
            case "notes": return notesComp;
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
        Component { id: notesComp; NotesTab { ctrl: root } }

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
