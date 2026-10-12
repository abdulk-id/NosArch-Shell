import QtQuick
import Quickshell
import Quickshell.Io

import "."

// IdleLockWidget — idle-lock indicator (ticket 17).
//
// INVERTED SEMANTICS (read before changing anything)
//
//   All reads and writes go through /usr/local/bin/nosarch/nosarch-session —
//   never systemctl, never a second source. The helper's words name the
//   *inhibit*, not the locking: `idle-lock status` prints `true` when the
//   nosarch-idle-inhibit unit is RUNNING, which means the machine will **not**
//   lock when idle. Taking "enabled" or `true` at face value inverts the
//   indicator. This widget shows whether the machine *will* lock when idle
//   (`willLockWhenIdle`), and passes toggle through the helper's `idle-lock
//   toggle`. The helper still carries a stale `pkill … waybar` against the old
//   bar; it becomes inert once waybar is retired (recorded in AGENTS.md, not
//   edited — NosArch-managed).
SimpleBarWidget {
    id: idleLock

    readonly property string sessionHelper: "/usr/local/bin/nosarch/nosarch-session"

    // Helper `true` == inhibit running == locking suppressed.
    property bool inhibitRunning: false
    readonly property bool willLockWhenIdle: !idleLock.inhibitRunning
    property bool statusKnown: false

    readonly property string barLabel: {
        if (!idleLock.statusKnown)
            return "…"
        return idleLock.willLockWhenIdle ? "󰾪" : "󰅶"
    }

    label: idleLock.barLabel

    tooltip: !idleLock.statusKnown
        ? "Reading idle-lock state…"
        : (idleLock.willLockWhenIdle
            ? "Will lock when idle — click to prevent"
            : "Will not lock when idle — click to restore locking")

    activate: function (widget) {
        toggleProc.running = true
    }

    function refreshStatus(): void {
        statusProc.running = true
    }

    Component.onCompleted: idleLock.refreshStatus()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: idleLock.refreshStatus()
    }

    Process {
        id: statusProc
        command: [idleLock.sessionHelper, "idle-lock", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim().toLowerCase()
                idleLock.inhibitRunning = (line === "true")
                idleLock.statusKnown = true
            }
        }
    }

    Process {
        id: toggleProc
        command: [idleLock.sessionHelper, "idle-lock", "toggle"]
        running: false
        onExited: idleLock.refreshStatus()
    }
}
