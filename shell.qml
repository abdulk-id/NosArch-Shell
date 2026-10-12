//@ pragma UseQApplication

import QtQuick

import Quickshell

import "shell"
import "shell/bar"
import "shell/notifications"
import "shell/osds"
import "shell/topisland"

ShellRoot {
    id: shell

    // Startup / reload lifecycle logging ---------------------------------------
    //
    // A reload re-evaluates this entire config as fresh QML objects, but it does
    // so in the SAME OS process. We stamp every evaluation with a plain
    // "fresh" or "reloaded" verdict so a state reset is never mistaken for a
    // clean start (spec, "Reload behaviour": "The shell logs whether it started
    // fresh or reloaded, so a state reset is distinguishable from a clean start").
    //
    // Why it is built this way — all verified on the installed Quickshell 0.3.2:
    //   * Persistent-property state does NOT survive a reload, so a remembered
    //     flag cannot tell the two apart, and object identity changes each cycle.
    //   * processId / instanceId / shellId / launchTime are all IDENTICAL across a
    //     fresh start and every reload (a reload does not fork a new process), so
    //     reading any of them cannot tell the two apart either.
    //   * Component.onCompleted therefore fires on BOTH a fresh start and a reload.
    //   * The one signal that differs is Quickshell.reloadCompleted: it fires once
    //     per reload and NEVER on a fresh start, and it is delivered synchronously
    //     while the reload completes — before control returns to the event loop —
    //     so a timer armed in Component.onCompleted is guaranteed to run AFTER it.
    //     That makes the verdict deterministic, not a timing race.
    //
    // The pid in the message is not printed by quickshell's own launch banner, so
    // it is added here: it stays the SAME across a reload (same process) and only
    // a genuinely fresh launch shows a new one, giving a second way to confirm the
    // verdict by eye.
    property bool _reloadSeen: false
    property bool _lifecycleLogged: false

    Connections {
        target: Quickshell
        function onReloadCompleted(): void {
            shell._reloadSeen = true;
        }
        function onReloadFailed(errorString): void {
            // A failed reload keeps the previously loaded config running; that
            // generation has already printed its verdict. Making the failure
            // visible stops a half-applied state reset from looking clean.
            console.warn("nosarch-shell ▸ RELOAD FAILED — still running the previous config: " + errorString);
        }
    }

    Component.onCompleted: settle.start();

    // Fires once the current reload (if any) has completed. reloadCompleted is
    // delivered synchronously ~1ms after the new config comes up and cannot arrive
    // later than this timer, so by the time it runs the flag is already correct:
    // set on a reload, still clear on a fresh start.
    Timer {
        id: settle
        interval: 50
        onTriggered: shell._logLifecycle();
    }

    function _logLifecycle(): void {
        if (shell._lifecycleLogged)
            return;
        shell._lifecycleLogged = true;
        if (shell._reloadSeen) {
            console.info("nosarch-shell ▸ RELOADED — this config was re-evaluated in the same running process (pid " + Quickshell.processId + "). All live state was reset; this is NOT a clean start.");
        } else {
            console.info("nosarch-shell ▸ STARTED FRESH — new shell process (pid " + Quickshell.processId + ").");
        }
    }
    // --------------------------------------------------------------------------

    Wallpaper {}

    // The bar's contents come from the user's configuration file. Touching the
    // BarConfig singleton here is what makes the real shell read it, validate
    // it and apply its failure policy — so a bad configuration file is reported
    // in the live shell's log, by name, rather than being a thing only the smoke
    // test knows about.
    //
    // It is REFERENCED, not declared: a `pragma Singleton` type is not
    // creatable, so `BarConfig {}` fails with "Composite Singleton Type
    // BarConfig is not creatable" — the same trap as createObject() on one.
    //
    // This is the READER, not the bar. No surface, no zones, nothing drawn:
    // arranging what it answers into three zones is ticket 08, and the
    // hardcoded bar below stays until ticket 18 retires it.
    readonly property var barConfiguration: BarConfig

    TopIsland {}

    ProgressOSDPanel {}
    MediaOsd {}
    NotificationPopup {}
}
