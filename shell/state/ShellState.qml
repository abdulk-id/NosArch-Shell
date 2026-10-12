pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ShellState — persisted shell preferences (ticket 16).
//
// State that must outlive the process lives in the framework's per-shell state
// directory (Quickshell.statePath), not in a service singleton and not in
// The framework's reloadable property helper does not survive a reload on the
// installed 0.3.2 build either — disk is the only durable seam here.
//
// Today this file holds only do-not-disturb. Later tickets add keys here rather
// than inventing a second persistence mechanism.
Singleton {
    id: shellState

    property bool doNotDisturb: false
    property bool _ready: false

    readonly property string stateFilePath: Quickshell.statePath("shell-state.json")

    property FileView store: FileView {
        id: stateFile

        path: shellState.stateFilePath
        preload: false
        blockLoading: false
        printErrors: false

        JsonAdapter {
            property bool doNotDisturb: false
        }

        onLoaded: shellState._hydrateFromFile()
        onAdapterUpdated: stateFile.writeAdapter()
    }

    function _hydrateFromFile(): void {
        stateFile.text()
        shellState.doNotDisturb = stateFile.adapter.doNotDisturb
        shellState._ready = true
        shellState._report()
    }

    onDoNotDisturbChanged: {
        if (!shellState._ready) {
            return
        }
        if (stateFile.adapter.doNotDisturb !== shellState.doNotDisturb) {
            stateFile.adapter.doNotDisturb = shellState.doNotDisturb
        }
    }

    Component.onCompleted: {
        stateFile.text()
        shellState.doNotDisturb = stateFile.adapter.doNotDisturb
        shellState._ready = true

        const probe = Quickshell.env("NOSARCH_SMOKE_DND")
        if (probe === "enable") {
            shellState.doNotDisturb = true
        }

        shellState._report()
    }

    function _report(): void {
        console.info("nosarch-shell ▸ STATE verdict path=" + shellState.stateFilePath +
            " doNotDisturb=" + shellState.doNotDisturb)
    }
}
