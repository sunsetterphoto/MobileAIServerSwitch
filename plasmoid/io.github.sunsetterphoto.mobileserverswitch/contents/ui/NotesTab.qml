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
 * overrule someone else's edit.
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
    property bool loading: false

    function load() {
        notesTab.loading = true;
        ctrl.notesLoad(function(text, code) {
            area.text = text;
            notesTab.dirty = false;
            notesTab.conflict = false;
            ctrl.notesMtime(function(m) {
                notesTab.loadedMtime = m;
                notesTab.loading = false;
            });
        });
    }

    // force = the user explicitly chose to overwrite
    function save(force) {
        if (!notesTab.dirty && !force) return;
        ctrl.notesMtime(function(m) {
            if (!force && m > notesTab.loadedMtime) {
                notesTab.conflict = true;   // do NOT write
                return;
            }
            ctrl.notesSave(area.text, function(code) {
                if (code === 0) {
                    notesTab.dirty = false;
                    notesTab.conflict = false;
                    ctrl.notesMtime(function(m2) { notesTab.loadedMtime = m2; });
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
            text: "Reload"
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
            wrapMode: TextEdit.Wrap
            placeholderText: "Notes about this machine — ports, commands, anything worth keeping."
            onTextChanged: {
                if (notesTab.loading) return;
                notesTab.dirty = true;
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
            text: notesTab.dirty ? "unsaved changes" : "saved"
        }
        PlasmaComponents3.Button {
            text: "Save"
            enabled: notesTab.dirty || notesTab.conflict
            onClicked: notesTab.save(notesTab.conflict)
        }
    }
}
