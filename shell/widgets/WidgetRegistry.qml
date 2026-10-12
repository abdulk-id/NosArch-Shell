pragma Singleton

import QtQml
import Quickshell

// WidgetRegistry — the name→file map (ticket 06).
//
// WHY A MAP AND NOT A PLUGIN REGISTRY
//
//   The framework provides no runtime plugin registry in the installed version
//   (verified against Quickshell 0.3.2 — see quickshell-api-notes.md), so there
//   is nothing to discover widgets through. The map is ours to maintain and it
//   is deliberately a literal: one line per widget, in shell code, reviewable in
//   a diff.
//
// WHY CONFIGURATION CANNOT CARRY A FILE PATH
//
//   The configuration file is user-owned and the installer ships it to every
//   target machine. If it could name an arbitrary file, editing configuration
//   would become executing code — a text file that decides which QML the shell
//   loads. So a name resolves ONLY through the `entries` map below, and an
//   unknown name resolves to nothing at all. Adding a widget means editing this
//   map, which is shell code, not a user-owned file.
//
// WHERE WIDGETS LIVE
//
//   shell/widgets/ — one predictable directory (spec story 88). The map's
//   values are file names resolved relative to this file's own directory, so
//   they are not paths and cannot escape the directory.
//
// ADDING A WIDGET
//
//   1. copy a file into shell/widgets/, extending BarWidget (or
//      SimpleBarWidget for a trivial label-plus-click widget),
//   2. add one line to `entries`,
//   3. add one line to shell/widgets/qmldir.
//
//   Nothing else changes. scripts/verify-widget-contract.sh fails if a widget
//   file has no registry name (unreachable from configuration) or a registry
//   name has no file (a name that resolves to nothing).
Singleton {
    id: registry

    // name → file name, relative to this directory. NOT a path: never a
    // leading slash, never a "..", never a directory. Scripts assert this.
    readonly property var entries: ({
        "clock": "ClockWidget.qml",
        // Kebab-case in configuration, UpperCamelCase as the file and the QML
        // type. The first widget that opens a PANEL rather than showing a label
        // (ticket 11), and so the first that needed presentation moved out of a
        // service: AudioService publishes state, VolumeWidget decides what it
        // looks like (ADR 0001).
        "volume": "VolumeWidget.qml",
        "network": "NetworkWidget.qml",
        "cpu": "CpuWidget.qml",
        "memory": "MemoryWidget.qml",
        "battery": "BatteryWidget.qml",
        "bluetooth": "BluetoothWidget.qml",
        "player": "PlayerWidget.qml",
        "launcher": "Launcher.qml",
        "workspaces": "Workspaces.qml",
        "tray": "Tray.qml",
        "notification": "NotificationWidget.qml",
        "idle-lock": "IdleLockWidget.qml"
    })

    // Every registered name, sorted — for logging and for the smoke readout.
    function names(): var {
        return Object.keys(registry.entries).sort()
    }

    // The file for a name, or null. Null is the answer for anything the map
    // does not hold, which is how an unknown configuration name is skipped
    // rather than resolved to somewhere unexpected.
    function fileFor(name): string {
        const f = registry.entries[name]
        return f === undefined ? null : f
    }

    // Whether a configuration name resolves at all.
    function isKnown(name): bool {
        return registry.fileFor(name) !== null
    }

    // The absolute URL for a name, resolved against THIS file's directory so
    // the map stays valid wherever the shell is installed. Null if unknown.
    function pathFor(name): string {
        const f = registry.fileFor(name)
        return f === null ? null : Qt.resolvedUrl(f)
    }

    // A loaded Component for a name, or null if the name is unknown. Callers
    // treat null as "skip this entry, log the name" rather than as an error:
    // a bad configuration must cost one missing widget, not the whole bar.
    function componentFor(name): Component {
        const p = registry.pathFor(name)
        return p === null ? null : Qt.createComponent(p)
    }
}