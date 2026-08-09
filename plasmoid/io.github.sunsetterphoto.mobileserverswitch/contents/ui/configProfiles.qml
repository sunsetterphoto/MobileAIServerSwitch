/*
 * Profiles: full editor for config.json's top-level "profiles" object (one
 * entry per profile id: label/icon plus display, power, locker,
 * charge-threshold, performance, services and radios sections -- see the
 * CLI contract / config/config.example.json). Stored as a single
 * JSON-string KConfigXT entry (profilesJson) because KConfigXT has no
 * native "map of objects" type; this page parses it into `profiles`,
 * mutates a JS copy and re-serializes on every change (same pattern as
 * configServices.qml / configFirewall.qml).
 *
 * Builtin profiles (server/laptop) can be edited and reset to their
 * canonical defaults, but not deleted. Custom profiles can be created,
 * duplicated and deleted freely. main.qml writes the result to config.json
 * via `msw-config-write --replace profiles`, so deletions propagate.
 *
 * Value convention throughout (per the CLI contract): null or "keep" means
 * "don't touch this setting when switching to the profile" -- shown as
 * "Keep" / "Don't change" in the UI.
 *
 * The settings dialog edits `cfg_profilesJson` (a working copy) until
 * Apply/OK; everything below therefore operates on that string, never on
 * Plasmoid.configuration.profilesJson directly.
 *
 * Two local Plasma5Support.DataSources run ONE-SHOT queries from this page
 * (config pages are independent component instances: they cannot see
 * main.qml's `exec`/`status`):
 *   - `kscreen-doctor -j`  -> resolution modes of the internal panel
 *   - `msw-status --json`  -> detected-but-unconfigured services
 * The PATH prefix mirrors main.qml (see its header comment for why).
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

ColumnLayout {
    id: page

    // Initial value and "Defaults" value = the canonical builtin profiles.
    // MUST stay in sync with the profilesJson <default> in
    // contents/config/main.xml (and main.qml's profilesDefaultJson).
    property string cfg_profilesJson: '{"server":{"label":"Server","icon":"network-server","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"ignore","power_button":"ignore","power_button_long":"ignore","auto_suspend":"ignore","auto_suspend_min":0,"screen_off_min":0,"dim_min":0,"wol":"on"},"locker":{"autolock":true,"timeout_min":15},"charge_thresholds":"40/80","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":["sunshine"],"stop":[]},"radios":{"wifi":"keep","bluetooth":"keep"}},"laptop":{"label":"Laptop","icon":"computer-laptop","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"sleep","power_button":"prompt","power_button_long":"shutdown","auto_suspend":"sleep","auto_suspend_min":30,"screen_off_min":10,"dim_min":5,"wol":"off"},"locker":{"autolock":true,"timeout_min":5},"charge_thresholds":"0/100","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":[],"stop":["sunshine"]},"radios":{"wifi":"on","bluetooth":"keep"}}}'
    property string cfg_profilesJsonDefault: '{"server":{"label":"Server","icon":"network-server","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"ignore","power_button":"ignore","power_button_long":"ignore","auto_suspend":"ignore","auto_suspend_min":0,"screen_off_min":0,"dim_min":0,"wol":"on"},"locker":{"autolock":true,"timeout_min":15},"charge_thresholds":"40/80","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":["sunshine"],"stop":[]},"radios":{"wifi":"keep","bluetooth":"keep"}},"laptop":{"label":"Laptop","icon":"computer-laptop","display":{"brightness":null,"resolution":null,"scale":null},"power":{"lid_action":"sleep","power_button":"prompt","power_button_long":"shutdown","auto_suspend":"sleep","auto_suspend_min":30,"screen_off_min":10,"dim_min":5,"wol":"off"},"locker":{"autolock":true,"timeout_min":5},"charge_thresholds":"0/100","performance":{"profile":"balanced","cpu_cap":null,"epp":null,"aspm":null,"dgpu":null},"services":{"start":[],"stop":["sunshine"]},"radios":{"wifi":"on","bluetooth":"keep"}}}'

    // Live-parsed working copy; re-evaluated whenever cfg_profilesJson
    // changes (including the initial load from the stored config).
    property var profiles: parseProfiles(cfg_profilesJson)

    // Currently edited profile id + object ({} when nothing valid is
    // selected -- every field below tolerates that).
    property string selectedId: ""
    readonly property var selected: {
        var p = profiles[selectedId];
        return (p && typeof p === "object" && !Array.isArray(p)) ? p : ({});
    }

    // Selector model: [{id, label, icon, builtin}] in insertion order.
    readonly property var profileList: {
        var out = [];
        var p = profiles;
        for (var k in p) {
            if (!p[k] || typeof p[k] !== "object") continue;
            out.push({ id: k,
                       label: p[k].label || k,
                       icon: p[k].icon || "dialog-question",
                       builtin: isBuiltin(k) });
        }
        return out;
    }

    // Resolution mode strings offered by the Display section (filled by the
    // kscreen-doctor one-shot below; stays [] when unavailable).
    property var resolutionModes: []

    // Installed-but-unconfigured services from `msw-status --json` (filled
    // by the status one-shot below; stays [] when unavailable).
    property var detectedServices: []

    // Globally configured services, read LIVE from the Services page's key
    // (cross-page pattern from the old configMode.qml: config pages are
    // independent instances, Plasmoid.configuration is the shared channel).
    readonly property var knownServices: parseServices(Plasmoid.configuration.servicesJson)

    // Checklist model for the two services lists. `.slice()` forces a new
    // array (and thus a Repeater rebuild with fresh `checked` state)
    // whenever `selected` changes -- referencing `selected` here is what
    // creates that re-evaluation dependency.
    readonly property var checklistModel: {
        var sel = selected;   // dependency, value unused
        return knownServices.slice();
    }

    readonly property var customStartEntries: customEntries("start")
    readonly property var customStopEntries: customEntries("stop")

    readonly property var defaultThresholds: ({ start: 40, end: 80 })

    // --- Enum option sets (text <-> stored value) ---------------------------
    readonly property var powerEventOptions: [
        { text: "Keep", value: "keep" }, { text: "Ignore", value: "ignore" },
        { text: "Sleep", value: "sleep" }, { text: "Shutdown", value: "shutdown" },
        { text: "Prompt", value: "prompt" }
    ]
    readonly property var onOffKeepOptions: [
        { text: "Keep", value: "keep" }, { text: "On", value: "on" },
        { text: "Off", value: "off" }
    ]
    readonly property var lockOptions: [
        { text: "Keep", value: "keep" }, { text: "On", value: true },
        { text: "Off", value: false }
    ]
    readonly property var perfProfileOptions: [
        { text: "Keep", value: null }, { text: "power-saver", value: "power-saver" },
        { text: "balanced", value: "balanced" }, { text: "performance", value: "performance" }
    ]
    readonly property var eppOptions: [
        { text: "Keep", value: null }, { text: "default", value: "default" },
        { text: "performance", value: "performance" },
        { text: "balance_performance", value: "balance_performance" },
        { text: "balance_power", value: "balance_power" },
        { text: "power", value: "power" }
    ]
    readonly property var aspmOptions: [
        { text: "Keep", value: null }, { text: "default", value: "default" },
        { text: "performance", value: "performance" },
        { text: "powersave", value: "powersave" },
        { text: "powersupersave", value: "powersupersave" }
    ]
    // Schema values null | "keep" | "auto" -- note "keep" means "keep the
    // dGPU AWAKE", while null means "don't change anything".
    readonly property var dgpuOptions: [
        { text: "Don't change", value: null }, { text: "Stay awake", value: "keep" },
        { text: "Auto-suspend", value: "auto" }
    ]
    readonly property var scaleOptions: [
        { text: "Keep current", value: null },
        { text: "1.0", value: 1.0 }, { text: "1.25", value: 1.25 },
        { text: "1.5", value: 1.5 }, { text: "1.75", value: 1.75 },
        { text: "2.0", value: 2.0 }, { text: "2.5", value: 2.5 },
        { text: "3.0", value: 3.0 }
    ]

    // --- Parsing / committing ------------------------------------------------
    function parseProfiles(json) {
        try {
            var o = JSON.parse(json);
            return (o && typeof o === "object" && !Array.isArray(o)) ? o : {};
        } catch (e) {
            return {};
        }
    }
    function parseServices(json) {
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }
    function commit(p) {
        profiles = p;
        cfg_profilesJson = JSON.stringify(p);
    }
    function profileIds() { return Object.keys(profiles); }
    function isBuiltin(id) { return id === "server" || id === "laptop"; }

    // Shallow-merge `patch` into profiles[id], then commit a fresh map.
    function updateProfile(id, patch) {
        if (!id) return;
        var next = {};
        for (var k in profiles) next[k] = profiles[k];
        var merged = {};
        var cur = profiles[id];
        if (cur && typeof cur === "object")
            for (k in cur) merged[k] = cur[k];
        for (k in patch) merged[k] = patch[k];
        next[id] = merged;
        commit(next);
    }
    // Shallow-merge `patch` into one NESTED section (display/power/locker/
    // performance/services/radios) of profiles[id].
    function updateSection(id, section, patch) {
        var curSec = sec(profiles[id], section);
        var merged = {};
        for (var k in curSec) merged[k] = curSec[k];
        for (k in patch) merged[k] = patch[k];
        var profPatch = {};
        profPatch[section] = merged;
        updateProfile(id, profPatch);
    }
    // Nested-section reader that never returns undefined/null/array.
    function sec(obj, name) {
        var s = obj ? obj[name] : null;
        return (s && typeof s === "object" && !Array.isArray(s)) ? s : ({});
    }
    // null/undefined -> "keep" (for enums whose keep value is the string).
    function keepNull(v) { return (v === null || v === undefined) ? "keep" : v; }
    // undefined -> null (for enums whose keep value is null).
    function nullUndef(v) { return v === undefined ? null : v; }

    onProfilesChanged: {
        // Keep the selection valid across commits/deletes.
        if (!profiles[selectedId]) {
            var ids = profileIds();
            selectedId = ids.length > 0 ? ids[0] : "";
        }
    }

    // --- Create / duplicate / delete / reset ---------------------------------
    function slugify(label) {
        // lowercase, [a-z0-9-] only; non-ASCII simply drops out (a label of
        // only umlauts falls back to "profile" in uniqueId()).
        return ("" + label).toLowerCase().replace(/[^a-z0-9-]+/g, "-")
                           .replace(/-+/g, "-").replace(/^-+|-+$/g, "");
    }
    function uniqueId(base) {
        var id = (base && base.length > 0) ? base : "profile";
        if (!profiles[id]) return id;
        var n = 2;
        while (profiles[id + "-" + n]) n++;
        return id + "-" + n;
    }
    // Generic template for NEW custom profiles (per the CLI contract):
    // everything "keep"/null/empty so a fresh profile changes nothing until
    // the user configures it.
    function newProfileTemplate(label) {
        return {
            label: label,
            icon: "dialog-question",
            display: { brightness: null, resolution: null, scale: null },
            power: { lid_action: "keep", power_button: "keep",
                     power_button_long: "keep", auto_suspend: "keep",
                     auto_suspend_min: 0, screen_off_min: null, dim_min: null,
                     wol: "keep" },
            locker: { autolock: "keep", timeout_min: 0 },
            charge_thresholds: null,
            performance: { profile: null, cpu_cap: null, epp: null,
                           aspm: null, dgpu: null },
            services: { start: [], stop: [] },
            radios: { wifi: "keep", bluetooth: "keep" }
        };
    }
    function createProfile(label) {
        label = (label || "").trim();
        if (label.length === 0) return;
        var id = uniqueId(slugify(label));
        var next = {};
        for (var k in profiles) next[k] = profiles[k];
        next[id] = newProfileTemplate(label);
        commit(next);
        selectedId = id;
    }
    function duplicateSelected() {
        var cur = profiles[selectedId];
        if (!cur) return;
        var copy = JSON.parse(JSON.stringify(cur));   // deep copy
        copy.label = (cur.label || selectedId) + " (copy)";
        var id = uniqueId(slugify(copy.label));
        var next = {};
        for (var k in profiles) next[k] = profiles[k];
        next[id] = copy;
        commit(next);
        selectedId = id;
    }
    function deleteSelected() {
        if (isBuiltin(selectedId)) return;   // builtin profiles can't be deleted
        var next = {};
        for (var k in profiles)
            if (k !== selectedId) next[k] = profiles[k];
        commit(next);   // onProfilesChanged re-selects the first remaining one
    }
    function resetSelectedToDefaults() {
        var d = parseProfiles(cfg_profilesJsonDefault)[selectedId];
        if (!d) return;
        var next = {};
        for (var k in profiles) next[k] = profiles[k];
        next[selectedId] = d;
        commit(next);
    }

    // --- Battery charge thresholds ("NN/NN" string <-> two ints) ------------
    function parseThresholds(s) {
        if (typeof s !== "string") return null;
        var m = /^(\d{1,3})\s*\/\s*(\d{1,3})$/.exec(s);
        if (!m) return null;
        var a = parseInt(m[1], 10), b = parseInt(m[2], 10);
        if (a > 100 || b > 100) return null;
        return { start: a, end: b };
    }

    // --- Services lists (start/stop) ------------------------------------------
    function serviceList(id, listName) {
        var a = sec(profiles[id], "services")[listName];
        return Array.isArray(a) ? a : [];
    }
    function serviceChecked(listName, svc) {
        if (!svc) return false;
        var arr = serviceList(selectedId, listName);
        return (!!svc.id && arr.indexOf(svc.id) >= 0)
               || (!!svc.unit && arr.indexOf(svc.unit) >= 0);
    }
    // A list entry may be a service id OR a unit name (CLI contract). The
    // checklist keys on id but also recognizes/removes the unit form, so a
    // unit-listed known service shows up checked and gets replaced by its
    // id on toggle.
    function toggleService(listName, svc, on) {
        if (!svc) return;
        var arr = serviceList(selectedId, listName).slice();
        function drop(key) {
            var i = arr.indexOf(key);
            if (i >= 0) arr.splice(i, 1);
        }
        if (svc.id) drop(svc.id);
        if (svc.unit) drop(svc.unit);
        if (on) arr.push(svc.id || svc.unit);
        var patch = {};
        patch[listName] = arr;
        updateSection(selectedId, "services", patch);
    }
    function addCustomService(listName, key) {
        key = (key || "").trim();
        if (key.length === 0) return;
        var arr = serviceList(selectedId, listName).slice();
        if (arr.indexOf(key) >= 0) return;
        arr.push(key);
        var patch = {};
        patch[listName] = arr;
        updateSection(selectedId, "services", patch);
    }
    function removeCustomService(listName, key) {
        var arr = serviceList(selectedId, listName).slice();
        var i = arr.indexOf(key);
        if (i < 0) return;
        arr.splice(i, 1);
        var patch = {};
        patch[listName] = arr;
        updateSection(selectedId, "services", patch);
    }
    function isKnownService(key) {
        if (!key) return false;
        for (var i = 0; i < knownServices.length; i++) {
            var s = knownServices[i];
            if (s && (s.id === key || s.unit === key)) return true;
        }
        return false;
    }
    // List entries that match no globally configured service (free-text
    // units/ids) -- shown separately with remove buttons.
    function customEntries(listName) {
        var arr = serviceList(selectedId, listName);
        var out = [];
        for (var i = 0; i < arr.length; i++)
            if (!isKnownService(arr[i])) out.push(arr[i]);
        return out;
    }
    // Adopt a detected service into the GLOBAL services list (the Services
    // page's servicesJson key). NOTE: this writes Plasmoid.configuration
    // directly -- it takes effect immediately (main.qml persists it to
    // config.json right away) and is NOT covered by this dialog's Cancel;
    // and a simultaneously edited Services page could overwrite it on
    // Apply. That tradeoff is deliberate ("self-detection shortcut").
    function adoptDetected(svc) {
        if (!svc) return;
        var arr = parseServices(Plasmoid.configuration.servicesJson);
        for (var i = 0; i < arr.length; i++)
            if (arr[i] && (arr[i].id === svc.id
                           || (!!svc.unit && arr[i].unit === svc.unit)))
                return;   // already known
        arr.push({
            id: svc.id || (svc.unit || "service").replace(/\.service$/, ""),
            label: svc.label || svc.id || svc.unit || "",
            unit: svc.unit || "",
            scope: svc.scope === "system" ? "system" : "user",
            port: (svc.port > 0) ? svc.port : 8080
        });
        Plasmoid.configuration.servicesJson = JSON.stringify(arr);
    }

    // --- One-shot probes (kscreen modes, detected services) -------------------
    readonly property string pathPrefix: {
        var bp = Plasmoid.configuration.binPath;
        var dirs = (bp && bp.length > 0) ? [bp] : [];
        dirs.push("$HOME/.local/bin", "/usr/local/bin");
        return "export PATH=\"" + dirs.join(":") + ":$PATH\"; ";
    }

    // kscreen-doctor -j -> mode-name strings of the internal panel (first
    // connected eDP* output; falls back to the first connected output).
    function parseKscreenModes(jsonText) {
        var out = [];
        try {
            var doc = JSON.parse(jsonText);
            var outputs = (doc && doc.outputs) || [];
            var panel = null;
            for (var i = 0; i < outputs.length; i++) {
                var o = outputs[i];
                if (!o || o.connected === false) continue;
                if (!panel && /^eDP/i.test(o.name || "")) panel = o;
            }
            if (!panel) {
                for (i = 0; i < outputs.length; i++)
                    if (outputs[i] && outputs[i].connected !== false) {
                        panel = outputs[i];
                        break;
                    }
            }
            var modes = (panel && panel.modes) || [];
            var seen = {};
            for (i = 0; i < modes.length; i++) {
                var m = modes[i];
                if (!m) continue;
                var name = m.name;
                if (!name && m.size)
                    name = m.size.width + "x" + m.size.height
                           + (m.refreshRate ? "@" + Math.round(m.refreshRate) : "");
                if (name && !seen[name]) {
                    seen[name] = true;
                    out.push(name);
                }
            }
        } catch (e) { /* keep [] */ }
        return out;
    }

    // msw-status --json -> detected-but-unconfigured services. Tolerant of
    // the exact placement (services.detected / services_detected / detected).
    function parseDetected(jsonText) {
        var out = [];
        try {
            var st = JSON.parse(jsonText);
            var s = st ? st.services : null;
            if (s && !Array.isArray(s) && Array.isArray(s.detected))
                out = s.detected;
            else if (st && Array.isArray(st.services_detected))
                out = st.services_detected;
            else if (st && Array.isArray(st.detected))
                out = st.detected;
        } catch (e) { /* keep [] */ }
        detectedServices = out;
    }

    Plasma5Support.DataSource {
        id: kscreenExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if ((data["exit code"] || 0) === 0)
                page.resolutionModes = page.parseKscreenModes(data["stdout"] || "");
            kscreenExec.disconnectSource(source);
        }
        Component.onCompleted: connectSource("kscreen-doctor -j")
    }

    Plasma5Support.DataSource {
        id: statusExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if ((data["exit code"] || 0) === 0)
                page.parseDetected(data["stdout"] || "");
            statusExec.disconnectSource(source);
        }
        Component.onCompleted: connectSource(page.pathPrefix + "msw-status --json")
    }

    // --- Reusable field controls ---------------------------------------------
    // All of these sync their visible state IMPERATIVELY from a stored-*
    // property (never via a declarative binding on the interactive property
    // itself): user interaction with a QQC2 control overwrites/breaks
    // bindings, so after every commit -- which replaces the whole `profiles`
    // object -- the changed stored-* input re-triggers sync(). The commit
    // signals (activated/valueModified/moved/textEdited/clicked) are all
    // user-interaction-only, so programmatic syncs never echo back.

    // ComboBox for enum-like values. `options` = [{text, value}].
    component EnumCombo: QQC2.ComboBox {
        property var options: []
        property var selectedValue
        signal chosen(var v)
        textRole: "text"
        model: options
        function sync() {
            var idx = 0;
            for (var i = 0; i < options.length; i++)
                if (options[i].value === selectedValue) { idx = i; break; }
            if (currentIndex !== idx) currentIndex = idx;
        }
        onOptionsChanged: sync()
        onCurrentValueChanged: sync()
        Component.onCompleted: sync()
        onActivated: (idx) => { if (options[idx]) chosen(options[idx].value); }
    }

    component IntSpin: QQC2.SpinBox {
        property int storedValue: 0
        signal spun(int v)
        function sync() { if (value !== storedValue) value = storedValue; }
        onStoredValueChanged: sync()
        Component.onCompleted: sync()
        onValueModified: spun(value)
    }

    component PctSlider: QQC2.Slider {
        property int storedValue: 0
        signal movedTo(int v)
        stepSize: 1
        function sync() { if (Math.round(value) !== storedValue) value = storedValue; }
        onStoredValueChanged: sync()
        Component.onCompleted: sync()
        onMoved: movedTo(Math.round(value))
    }

    component SyncCheck: QQC2.CheckBox {
        property bool storedChecked: false
        signal checkToggled(bool on)
        function sync() { if (checked !== storedChecked) checked = storedChecked; }
        onStoredCheckedChanged: sync()
        Component.onCompleted: sync()
        onClicked: checkToggled(checked)
    }

    component SyncField: QQC2.TextField {
        property string storedText: ""
        signal editedText(string t)
        function sync() { if (text !== storedText) text = storedText; }
        onStoredTextChanged: sync()
        Component.onCompleted: sync()
        onTextEdited: editedText(text)
    }

    component SectionHeader: QQC2.Label {
        font.bold: true
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "Profiles that can be switched in the Mode tab. \"Keep\" / \"Don't change\" leaves a setting untouched when switching to the profile."
    }

    // --- Profile selector + actions -------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.ComboBox {
            id: profilePicker
            Layout.fillWidth: true
            textRole: "label"
            model: page.profileList
            function sync() {
                var idx = 0;
                for (var i = 0; i < page.profileList.length; i++)
                    if (page.profileList[i].id === page.selectedId) { idx = i; break; }
                if (currentIndex !== idx) currentIndex = idx;
            }
            onModelChanged: sync()
            Component.onCompleted: sync()
            onActivated: (idx) => {
                if (page.profileList[idx]) page.selectedId = page.profileList[idx].id;
            }
            Connections {
                target: page
                function onSelectedIdChanged() { profilePicker.sync(); }
            }
        }
        QQC2.Button {
            icon.name: "list-add"
            text: "New"
            onClicked: newDialog.open()
        }
        QQC2.Button {
            icon.name: "edit-copy"
            text: "Duplicate"
            enabled: page.selectedId.length > 0
            onClicked: page.duplicateSelected()
        }
        QQC2.Button {
            icon.name: "edit-delete"
            text: "Delete"
            enabled: page.selectedId.length > 0 && !page.isBuiltin(page.selectedId)
            onClicked: page.deleteSelected()
        }
        QQC2.Button {
            icon.name: "edit-undo"
            text: "Reset to defaults"
            visible: page.isBuiltin(page.selectedId)
            onClicked: page.resetSelectedToDefaults()
        }
    }

    // --- General ---------------------------------------------------------------
    SectionHeader { text: "General" }
    Kirigami.FormLayout {
        Layout.fillWidth: true
        SyncField {
            Kirigami.FormData.label: "Label:"
            Layout.fillWidth: true
            storedText: page.selected.label || ""
            onEditedText: (t) => page.updateProfile(page.selectedId, { label: t })
        }
        SyncField {
            Kirigami.FormData.label: "Icon:"
            Layout.fillWidth: true
            placeholderText: "network-server"
            storedText: page.selected.icon || ""
            onEditedText: (t) => page.updateProfile(page.selectedId, { icon: t })
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: "Icon name from the current icon theme (e.g. network-server, computer-laptop)."
        }
    }

    // --- Display ---------------------------------------------------------------
    SectionHeader { text: "Display" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: "Brightness:"
            spacing: Kirigami.Units.smallSpacing
            SyncCheck {
                id: brightnessCheck
                text: "Set"
                storedChecked: {
                    var v = page.sec(page.selected, "display").brightness;
                    return v !== null && v !== undefined;
                }
                onCheckToggled: (on) => {
                    var cur = page.sec(page.selected, "display").brightness;
                    page.updateSection(page.selectedId, "display",
                        { brightness: on ? ((cur !== null && cur !== undefined) ? cur : 50) : null });
                }
            }
            PctSlider {
                id: brightnessSlider
                Layout.fillWidth: true
                from: 0
                to: 100
                enabled: brightnessCheck.checked
                storedValue: {
                    var v = page.sec(page.selected, "display").brightness;
                    return (v !== null && v !== undefined) ? v : 50;
                }
                onMovedTo: (v) => page.updateSection(page.selectedId, "display",
                                                     { brightness: v })
            }
            QQC2.Label { text: Math.round(brightnessSlider.value) + " %" }
        }

        // Resolution: "Keep current" + modes of the internal panel (from the
        // kscreen-doctor one-shot above). Editable so a mode string can also
        // be typed by hand -- the only option when kscreen-doctor is absent.
        QQC2.ComboBox {
            id: resCombo
            Kirigami.FormData.label: "Resolution:"
            Layout.fillWidth: true
            editable: true
            model: ["Keep current"].concat(page.resolutionModes)
            function sync() {
                var v = page.sec(page.selected, "display").resolution;
                if (v === null || v === undefined || v === "") {
                    currentIndex = 0;
                    editText = "";
                } else {
                    var idx = model.indexOf(v);
                    currentIndex = idx;   // -1 (= custom text) when not listed
                    editText = v;
                }
            }
            onModelChanged: sync()
            Component.onCompleted: sync()
            Connections {
                target: page
                function onSelectedChanged() { resCombo.sync(); }
            }
            onActivated: (idx) => page.updateSection(page.selectedId, "display",
                { resolution: idx <= 0 ? null : model[idx] })
            onAccepted: {
                var t = (editText || "").trim();
                page.updateSection(page.selectedId, "display",
                    { resolution: (t.length === 0 || t === "Keep current") ? null : t });
            }
        }

        EnumCombo {
            Kirigami.FormData.label: "Scale:"
            options: page.scaleOptions
            selectedValue: page.nullUndef(page.sec(page.selected, "display").scale)
            onChosen: (v) => page.updateSection(page.selectedId, "display", { scale: v })
        }
    }

    // --- Power -------------------------------------------------------------------
    SectionHeader { text: "Power" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        EnumCombo {
            Kirigami.FormData.label: "Lid closed:"
            options: page.powerEventOptions
            selectedValue: page.keepNull(page.sec(page.selected, "power").lid_action)
            onChosen: (v) => page.updateSection(page.selectedId, "power", { lid_action: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "Power button:"
            options: page.powerEventOptions
            selectedValue: page.keepNull(page.sec(page.selected, "power").power_button)
            onChosen: (v) => page.updateSection(page.selectedId, "power", { power_button: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "Power button (long):"
            options: page.powerEventOptions
            selectedValue: page.keepNull(page.sec(page.selected, "power").power_button_long)
            onChosen: (v) => page.updateSection(page.selectedId, "power", { power_button_long: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "Auto-suspend:"
            options: page.powerEventOptions
            selectedValue: page.keepNull(page.sec(page.selected, "power").auto_suspend)
            onChosen: (v) => page.updateSection(page.selectedId, "power", { auto_suspend: v })
        }
        IntSpin {
            Kirigami.FormData.label: "Auto-suspend after (min):"
            from: 0
            to: 480
            storedValue: page.sec(page.selected, "power").auto_suspend_min || 0
            onSpun: (v) => page.updateSection(page.selectedId, "power", { auto_suspend_min: v })
        }
        // screen_off_min / dim_min: null = keep (don't touch), 0 = never
        // (actively disable), N = minutes -- hence the "Set" checkbox, same
        // pattern as the brightness control above.
        SyncCheck {
            id: screenOffSet
            Kirigami.FormData.label: "Screen off:"
            text: "set (minutes, 0 = never)"
            storedChecked: page.sec(page.selected, "power").screen_off_min !== null
                           && page.sec(page.selected, "power").screen_off_min !== undefined
            onCheckToggled: (on) => page.updateSection(page.selectedId, "power",
                { screen_off_min: on ? (page.sec(page.selected, "power").screen_off_min || 10) : null })
        }
        IntSpin {
            enabled: screenOffSet.checked
            from: 0
            to: 480
            storedValue: page.sec(page.selected, "power").screen_off_min || 10
            onSpun: (v) => page.updateSection(page.selectedId, "power", { screen_off_min: v })
        }
        SyncCheck {
            id: dimSet
            Kirigami.FormData.label: "Dim screen:"
            text: "set (minutes, 0 = never)"
            storedChecked: page.sec(page.selected, "power").dim_min !== null
                           && page.sec(page.selected, "power").dim_min !== undefined
            onCheckToggled: (on) => page.updateSection(page.selectedId, "power",
                { dim_min: on ? (page.sec(page.selected, "power").dim_min || 5) : null })
        }
        IntSpin {
            enabled: dimSet.checked
            from: 0
            to: 480
            storedValue: page.sec(page.selected, "power").dim_min || 5
            onSpun: (v) => page.updateSection(page.selectedId, "power", { dim_min: v })
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: "Unchecked = keep the current setting; 0 min = never."
        }
        EnumCombo {
            Kirigami.FormData.label: "Wake-on-LAN:"
            options: page.onOffKeepOptions
            selectedValue: page.keepNull(page.sec(page.selected, "power").wol)
            onChosen: (v) => page.updateSection(page.selectedId, "power", { wol: v })
        }
    }

    // --- Lock screen -------------------------------------------------------------
    SectionHeader { text: "Lock screen" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        EnumCombo {
            Kirigami.FormData.label: "Auto-lock:"
            options: page.lockOptions
            selectedValue: page.keepNull(page.sec(page.selected, "locker").autolock)
            onChosen: (v) => page.updateSection(page.selectedId, "locker", { autolock: v })
        }
        IntSpin {
            Kirigami.FormData.label: "Lock after (min):"
            from: 0
            to: 600
            storedValue: page.sec(page.selected, "locker").timeout_min || 0
            onSpun: (v) => page.updateSection(page.selectedId, "locker", { timeout_min: v })
        }
    }

    // --- Battery -----------------------------------------------------------------
    SectionHeader { text: "Battery" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        SyncCheck {
            id: threshCheck
            Kirigami.FormData.label: "Charge thresholds:"
            text: "Set charge thresholds (only if the hardware supports it)"
            storedChecked: page.parseThresholds(page.selected.charge_thresholds) !== null
            onCheckToggled: (on) => {
                if (on) {
                    var t = page.parseThresholds(page.selected.charge_thresholds)
                            || page.defaultThresholds;
                    page.updateProfile(page.selectedId,
                        { charge_thresholds: t.start + "/" + t.end });
                } else {
                    page.updateProfile(page.selectedId, { charge_thresholds: null });
                }
            }
        }
        IntSpin {
            id: threshStart
            Kirigami.FormData.label: "Start (%):"
            from: 0
            to: 100
            enabled: threshCheck.checked
            storedValue: (page.parseThresholds(page.selected.charge_thresholds)
                          || page.defaultThresholds).start
            onSpun: (v) => {
                var t = page.parseThresholds(page.selected.charge_thresholds)
                        || page.defaultThresholds;
                page.updateProfile(page.selectedId,
                    { charge_thresholds: v + "/" + t.end });
            }
        }
        IntSpin {
            id: threshEnd
            Kirigami.FormData.label: "End (%):"
            from: 0
            to: 100
            enabled: threshCheck.checked
            storedValue: (page.parseThresholds(page.selected.charge_thresholds)
                          || page.defaultThresholds).end
            onSpun: (v) => {
                var t = page.parseThresholds(page.selected.charge_thresholds)
                        || page.defaultThresholds;
                page.updateProfile(page.selectedId,
                    { charge_thresholds: t.start + "/" + v });
            }
        }
    }

    // --- Performance ---------------------------------------------------------------
    SectionHeader { text: "Performance" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        EnumCombo {
            Kirigami.FormData.label: "Profile:"
            options: page.perfProfileOptions
            selectedValue: page.nullUndef(page.sec(page.selected, "performance").profile)
            onChosen: (v) => page.updateSection(page.selectedId, "performance", { profile: v })
        }
        RowLayout {
            Kirigami.FormData.label: "CPU cap:"
            spacing: Kirigami.Units.smallSpacing
            SyncCheck {
                id: cpuCapCheck
                text: "Set"
                storedChecked: {
                    var v = page.sec(page.selected, "performance").cpu_cap;
                    return v !== null && v !== undefined;
                }
                onCheckToggled: (on) => {
                    var cur = page.sec(page.selected, "performance").cpu_cap;
                    page.updateSection(page.selectedId, "performance",
                        { cpu_cap: on ? ((cur !== null && cur !== undefined) ? cur : 100) : null });
                }
            }
            PctSlider {
                id: cpuCapSlider
                Layout.fillWidth: true
                from: 16
                to: 100
                enabled: cpuCapCheck.checked
                storedValue: {
                    var v = page.sec(page.selected, "performance").cpu_cap;
                    return (v !== null && v !== undefined) ? v : 100;
                }
                onMovedTo: (v) => page.updateSection(page.selectedId, "performance",
                                                     { cpu_cap: v })
            }
            QQC2.Label { text: Math.round(cpuCapSlider.value) + " %" }
        }
        EnumCombo {
            Kirigami.FormData.label: "EPP:"
            options: page.eppOptions
            selectedValue: page.nullUndef(page.sec(page.selected, "performance").epp)
            onChosen: (v) => page.updateSection(page.selectedId, "performance", { epp: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "ASPM:"
            options: page.aspmOptions
            selectedValue: page.nullUndef(page.sec(page.selected, "performance").aspm)
            onChosen: (v) => page.updateSection(page.selectedId, "performance", { aspm: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "dGPU:"
            options: page.dgpuOptions
            selectedValue: page.nullUndef(page.sec(page.selected, "performance").dgpu)
            onChosen: (v) => page.updateSection(page.selectedId, "performance", { dgpu: v })
        }
    }

    // --- Services -------------------------------------------------------------------
    SectionHeader { text: "Services" }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: "Start when switching to this profile:" }
        Repeater {
            model: page.checklistModel
            delegate: SyncCheck {
                required property var modelData
                Layout.fillWidth: true
                text: (modelData.label || modelData.id)
                      + (modelData.unit ? "  (" + modelData.unit + ")" : "")
                storedChecked: page.serviceChecked("start", modelData)
                onCheckToggled: (on) => page.toggleService("start", modelData, on)
            }
        }
        Repeater {
            model: page.customStartEntries
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData
                    opacity: 0.7
                }
                QQC2.Button {
                    icon.name: "list-remove"
                    flat: true
                    onClicked: page.removeCustomService("start", modelData)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.TextField {
                id: customStartField
                Layout.fillWidth: true
                placeholderText: "service id or unit name"
                onAccepted: customStartAdd.clicked()
            }
            QQC2.Button {
                id: customStartAdd
                text: "Add"
                icon.name: "list-add"
                enabled: customStartField.text.trim().length > 0
                onClicked: {
                    page.addCustomService("start", customStartField.text);
                    customStartField.text = "";
                }
            }
        }

        QQC2.Label {
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: "Stop when switching to this profile:"
        }
        Repeater {
            model: page.checklistModel
            delegate: SyncCheck {
                required property var modelData
                Layout.fillWidth: true
                text: (modelData.label || modelData.id)
                      + (modelData.unit ? "  (" + modelData.unit + ")" : "")
                storedChecked: page.serviceChecked("stop", modelData)
                onCheckToggled: (on) => page.toggleService("stop", modelData, on)
            }
        }
        Repeater {
            model: page.customStopEntries
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData
                    opacity: 0.7
                }
                QQC2.Button {
                    icon.name: "list-remove"
                    flat: true
                    onClicked: page.removeCustomService("stop", modelData)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.TextField {
                id: customStopField
                Layout.fillWidth: true
                placeholderText: "service id or unit name"
                onAccepted: customStopAdd.clicked()
            }
            QQC2.Button {
                id: customStopAdd
                text: "Add"
                icon.name: "list-add"
                enabled: customStopField.text.trim().length > 0
                onClicked: {
                    page.addCustomService("stop", customStopField.text);
                    customStopField.text = "";
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: page.knownServices.length === 0
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: "No services configured yet -- add some on the Services page, adopt detected ones below, or enter a unit name directly."
        }

        // Detected-but-unconfigured services (from the msw-status one-shot
        // above); "Add" adopts them into the global Services list so they
        // become checklist entries here.
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.detectedServices.length > 0
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Detected on this system (Add = adopt into the Services list, applies immediately):"
            }
            Repeater {
                model: page.detectedServices
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: (modelData.label || modelData.id || modelData.unit || "?")
                              + (modelData.unit ? "  (" + modelData.unit + ")" : "")
                    }
                    QQC2.Button {
                        text: "Add"
                        icon.name: "list-add"
                        enabled: !page.isKnownService(modelData.id)
                                 && !page.isKnownService(modelData.unit)
                        onClicked: page.adoptDetected(modelData)
                    }
                }
            }
        }
    }

    // --- Radios -------------------------------------------------------------------
    SectionHeader { text: "Radios" }
    Kirigami.FormLayout {
        Layout.fillWidth: true

        EnumCombo {
            Kirigami.FormData.label: "WiFi:"
            options: page.onOffKeepOptions
            selectedValue: page.keepNull(page.sec(page.selected, "radios").wifi)
            onChosen: (v) => page.updateSection(page.selectedId, "radios", { wifi: v })
        }
        EnumCombo {
            Kirigami.FormData.label: "Bluetooth:"
            options: page.onOffKeepOptions
            selectedValue: page.keepNull(page.sec(page.selected, "radios").bluetooth)
            onChosen: (v) => page.updateSection(page.selectedId, "radios", { bluetooth: v })
        }
    }

    Item { Layout.fillHeight: true }

    // --- "New profile" name dialog ------------------------------------------------
    QQC2.Dialog {
        id: newDialog
        title: "New profile"
        modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent

        contentItem: QQC2.TextField {
            id: newNameField
            implicitWidth: Kirigami.Units.gridUnit * 16
            placeholderText: "Profile name (e.g. Presentation)"
            onAccepted: newDialog.accept()
        }
        onOpened: {
            newNameField.text = "";
            newNameField.forceActiveFocus();
        }
        // The id is derived from the label (slugified, collision-safe).
        onAccepted: page.createProfile(newNameField.text)
    }
}
