/*
 * Notes tab: a scratchpad for things worth remembering about this machine.
 *
 * The notes live in a plain file (~/.config/mobileserverswitch/notes.md,
 * mode 600) and are read/written through msw-notes -- never through
 * msw-status, because notes tend to contain credentials and that JSON is
 * handed around freely.
 *
 * Saving is debounced and also happens when the popup closes. If the file
 * changed underneath us (an SSH session, an editor), an automatic save is
 * SUPPRESSED and the user is asked -- an automatic action must never
 * overrule someone else's edit. The freshness check right before writing
 * (save()'s ctrl.notesMtime() call below) is the actual guard; the mtime it
 * compares against (loadedMtime) is adopted ONLY from msw-notes' own output
 * (load()'s single `read` invocation -- which prints the mtime it read on
 * stderr, immediately before printing the content, as part of that SAME
 * call -- or write's printed mtime on success) -- never from a second,
 * separate round trip that could itself race an external writer.
 *
 * A file that EXISTS but could not be read (permissions -- most realistically
 * after a `sudo $EDITOR` over SSH leaves it root-owned -- or a directory
 * sitting at the notes path) is reported by msw-notes as a distinct failure,
 * never as empty. load() turns that into loadFailed: the pad is shown
 * disabled with an explanation instead of an empty, editable textarea, and
 * save() refuses to run at all while loadFailed is set -- regardless of how
 * dirty became true or which caller (debounce, popup close, the Save
 * button) invoked it. Presenting an empty pad for an unreadable file would
 * let the very next autosave silently destroy content that is still on
 * disk, since `mv -f` in msw-notes write only needs directory write
 * permission, never permission to read the file it replaces.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: notesTab
    property var ctrl
    spacing: Kirigami.Units.smallSpacing

    property int loadedMtime: 0
    property bool dirty: false
    property bool conflict: false
    property bool saveError: false
    // Set when the most recent load() could not read the file at all (exit
    // code != 0 from `msw-notes read`: permission denied, or a directory at
    // the notes path). While true: the textarea is disabled (never an
    // editable-looking empty pad standing in for content that may still be
    // on disk), and save() refuses unconditionally -- see save() below.
    property bool loadFailed: false
    // Set right before load() assigns area.text, consumed by the very next
    // TextArea.onTextChanged -- suppresses ONLY that one programmatic
    // assignment, not "every change for a while" (a stuck window-style flag
    // previously discarded real keystrokes typed while a load was in
    // flight). See the fallback reset in load() for the case where the
    // assignment doesn't actually change the text (nothing to suppress).
    property bool suppressNextChange: false

    function load() {
        ctrl.notesLoad(function(text, code, mtime) {
            if (code !== 0) {
                // Do NOT touch area.text here: leaving whatever was already
                // shown (typically nothing, on the very first load) is
                // strictly safer than assigning "", which would look
                // exactly like a genuinely empty file. Either way the pad
                // is about to be disabled below, so nothing further can be
                // typed into it regardless.
                notesTab.loadFailed = true;
                notesTab.dirty = false;
                notesTab.conflict = false;
                notesTab.saveError = false;
                debounce.stop(); // no pending autosave may survive a failed (re)load
                return;
            }
            notesTab.loadFailed = false;
            notesTab.suppressNextChange = true;
            area.text = text;
            // QML's TextEdit/TextArea "text" property notifies synchronously
            // on a direct assignment, so if the line above actually changed
            // the text, onTextChanged has already run and cleared the flag
            // by now. If it did NOT change the text (e.g. loading "" into an
            // already-empty area), no signal fired at all and the flag would
            // otherwise stay stuck true, silently swallowing the very next
            // real keystroke -- clear it explicitly to cover that case.
            notesTab.suppressNextChange = false;
            notesTab.dirty = false;
            notesTab.conflict = false;
            notesTab.saveError = false;
            // Adopted from THIS SAME `read` invocation's stderr (see
            // ctrl.notesLoad in main.qml) -- not a second, separate `mtime`
            // call, which would reopen the exact race this tab exists to
            // close (an external writer landing in the gap getting silently
            // adopted as "the mtime we loaded at").
            notesTab.loadedMtime = mtime;
        });
    }

    // force = the user explicitly chose to overwrite (the "Save anyway"
    // button in the conflict banner -- nothing else passes true, see the
    // "Save" button below).
    function save(force) {
        // Never write over a file this tab could not even read -- true
        // regardless of force, and regardless of which caller triggered
        // save() (debounce timer, popup close, the Save/Save-anyway
        // buttons): none of them can observe dirty becoming true while the
        // pad is disabled, but this guard does not rely on that being the
        // only way in -- it is the actual, unconditional stop.
        if (notesTab.loadFailed) return;
        if (!notesTab.dirty && !force) return;
        ctrl.notesMtime(function(m) {
            if (!force && m > notesTab.loadedMtime) {
                notesTab.conflict = true;   // do NOT write
                notesTab.saveError = false; // the conflict banner already explains the situation
                return;
            }
            ctrl.notesSave(area.text, function(code, mtime) {
                if (code === 0) {
                    notesTab.dirty = false;
                    notesTab.conflict = false;
                    notesTab.saveError = false;
                    // Adopted straight from write's own stdout (the mtime it
                    // set, printed as part of the same invocation) -- NOT
                    // from a second "msw-notes mtime" call, which would
                    // reopen exactly the race this tab exists to close: an
                    // external writer landing between our write and that
                    // second read would get its mtime silently adopted as
                    // "ours", masking the very next external edit.
                    notesTab.loadedMtime = mtime;
                } else {
                    notesTab.saveError = true;
                }
            });
        });
    }

    Component.onCompleted: load()

    // Save when the popup closes -- the most common way to leave the tab.
    Connections {
        target: notesTab.ctrl
        function onExpandedChanged() {
            if (!notesTab.ctrl.expanded && notesTab.dirty) notesTab.save(false);
        }
    }

    Timer {
        id: debounce
        interval: 1500
        repeat: false
        onTriggered: notesTab.save(false)
    }

    RowLayout {
        Layout.fillWidth: true
        visible: notesTab.loadFailed
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "dialog-error"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            // The two realistic causes, named directly: permission denied
            // (most often a `sudo $EDITOR` over SSH leaving the file
            // root-owned) and a directory sitting at the notes path.
            // Nothing is saved while this shows -- see save()'s loadFailed
            // guard above.
            text: "Notes could not be read (permission denied, or the notes path is a directory). Nothing will be saved until this is fixed."
        }
        PlasmaComponents3.Button {
            text: "Retry"
            onClicked: notesTab.load()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: notesTab.conflict
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "dialog-warning"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: "The file changed elsewhere. Nothing was saved."
        }
        PlasmaComponents3.Button {
            // States what it will discard: Reload always replaces the
            // textarea with the on-disk version, and there IS something to
            // lose here specifically -- a conflict means the automatic save
            // that would have run was suppressed, so notesTab.dirty is still
            // true (the in-progress edit was never written anywhere).
            text: notesTab.dirty ? "Discard local changes, reload" : "Reload"
            onClicked: notesTab.load()
        }
        PlasmaComponents3.Button {
            text: "Save anyway"
            onClicked: notesTab.save(true)
        }
    }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        PlasmaComponents3.TextArea {
            id: area
            enabled: !notesTab.loadFailed
            wrapMode: TextEdit.Wrap
            placeholderText: notesTab.loadFailed ? "" : "Notes about this machine — ports, commands, anything worth keeping."
            onTextChanged: {
                if (notesTab.suppressNextChange) {
                    notesTab.suppressNextChange = false;
                    return;
                }
                notesTab.dirty = true;
                notesTab.saveError = false;
                debounce.restart();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            opacity: 0.6
            font: Kirigami.Theme.smallFont
            color: notesTab.saveError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            text: notesTab.loadFailed ? "notes unreadable -- see above"
                  : notesTab.saveError ? "save failed -- click Save to retry"
                  : (notesTab.dirty ? "unsaved changes" : "saved")
        }
        PlasmaComponents3.Button {
            // Deliberately always re-checks freshness (force: false), same
            // as the automatic path -- it never silently overwrites. Only
            // "Save anyway" in the conflict banner above does that, and only
            // because its label says so. Disabled while a conflict is
            // already showing: the banner's own two buttons (Reload / Save
            // anyway) are the only way to resolve it, so this button staying
            // enabled there would just be a confusing, silent no-op click.
            // Also disabled while loadFailed -- the Retry button in that
            // banner is the only way forward, and save() would refuse
            // anyway (belt and suspenders, not the only guard).
            text: "Save"
            enabled: (notesTab.dirty || notesTab.saveError) && !notesTab.conflict && !notesTab.loadFailed
            onClicked: notesTab.save(false)
        }
    }
}
