//@ pragma UseQApplication
//
// smoke.qml — instantiation-only smoke test for the whole shell.
//
// WHY THIS FILE EXISTS
//
// Nothing used to object when a widget broke: Quickshell only prints QML
// errors (type errors, missing properties, unresolved bindings) to its log and
// still exits 0, so a half-wired widget was invisible until someone looked at
// the bar. This entrypoint is the single verification seam: it instantiates
// every widget, every service and every shared component, then reports each
// one BY NAME so a failure is attributable to a file.
//
// WHAT IT DOES *NOT* DO
//
//   * It asserts no behaviour — no pixel geometry, no input, no layout. The
//     framework has no unit test runner; this is a harness, not a test suite.
//   * It draws no layer-shell surfaces. Every instantiated object is parented
//     to plain in-memory Items, so nothing appears on screen and the live bar
//     (waybar) is never involved or replaced.
//   * It cannot instantiate shell.qml itself: loaded as a component of
//     another config, its directory imports do not resolve — a config's
//     local-dir types only work when the file IS the config root (verified:
//     `TopIsland is not a type`). The assembled root shell is covered by
//     scripts/verify-launch-reload.sh, which launches the real shell by path.
//
// HOW FAILURE IS DETECTED (this file cannot fail on its own)
//
// Quickshell exits 0 even when every binding throws, so the exit code of
// `quickshell -p smoke.qml` means nothing. scripts/verify-smoke.sh is the
// judge: it (a) requires a PASS line for every planned item, and (b) scans the
// log for WARN/ERROR lines and fails on any that name a file in this repo.
// This file only has to report truthfully and quit; the script decides.
//
// WHY THE WAITING PERIODS
//
// Services populate asynchronously (pipewire, NetworkManager, UPower all
// answer a moment after the shell starts). A widget instantiated at t=0 reads
// null sub-objects and logs transient "of null" TypeErrors that are NOT
// bugs. So the smoke shell waits for the hardware the widgets actually
// dereference to answer (capped, then it proceeds and says so) and takes the
// service readouts a moment after that. Waiting beats guessing a delay: the
// log is equally clean on a fast and a slow machine.

import QtQuick

import Quickshell
import Quickshell.Networking

// Registered services (see services/qmldir). Referencing the singletons here
// is what creates them, so a service that cannot even be constructed fails.
import "services" as Services

// The ui singletons (Colors, Fonts — see shell/ui/qmldir). Referencing them
// here constructs them, so a palette that cannot load fails in the smoke run.
import "shell/ui" as UI

// The widget contract's registry (see shell/widgets/qmldir). Referencing the
// singleton constructs it, so a registry that cannot load fails the smoke run.
import "shell/widgets" as Widgets

// The panel architecture (see shell/panels/qmldir, ticket 11). Referencing the
// coordinator and the card here constructs them, so neither can rot without a
// smoke run noticing. The SURFACE is only loaded — see configPlan.
import "shell/panels" as Panels

// The shared components, including the volume PRESENTATION that moved out of
// AudioService in ticket 11 (ADR 0001).
import "components" as Components

// The bar's configuration reader and one zone (see shell/bar/qmldir, ticket 07).
// Referencing BarConfig here constructs it, which is what makes the file
// reader and its failure policy part of every smoke run.
import "shell/bar" as Bar

import "shell/state" as State

Item {
    id: smokeRoot

    // ------------------------------------------------------------------ timing

    // How long the widgets' hardware gets to answer, and how long widgets get
    // before the service readouts are taken. Widgets bind to sub-objects that
    // are null until their hardware answers (pipewire, NetworkManager), and a
    // widget instantiated too early logs a transient "of null" TypeError that
    // is NOT a defect — so the log is only deterministic once the hardware has
    // settled. Waiting for the answer (capped) beats guessing a delay: the run
    // is equally deterministic on a fast and a slow machine. If the cap is
    // hit, the log says so and any warning that follows is a real defect.
    readonly property int hardwareCapMs: parseInt(Quickshell.env("SMOKE_HARDWARE_CAP_MS")) || 8000
    readonly property int screenWaitMs: parseInt(Quickshell.env("SMOKE_SCREEN_WAIT_MS")) || 2000
    readonly property int finalSettleMs: parseInt(Quickshell.env("SMOKE_FINAL_MS")) || 1500

    readonly property double t0: Date.now()
    property int stage: 0
    property double stage1At: 0
    property var screenHosts: []          // [{name, host}] — one per attached screen

    // The exact sub-objects a widget dereferences. Waiting for these is what
    // removes the null-transient churn; if the machine has no such hardware
    // the cap expires and the smoke test reports whatever warning is real.
    function hardwareSettled(): bool {
        const audio = Services.AudioService;
        if (audio.output.defaultSink === null || audio.input.defaultSource === null) {
            return false;
        }
        return Services.NetworkService.activeNetwork !== null;
    }

    // --------------------------------------------------------------- reporting

    property var planned: []              // {kind, name}
    property var results: []              // {kind, name, ok, detail}

    function plan(kind: string, name: string): void {
        smokeRoot.planned.push({ kind: kind, name: name });
        console.info("SMOKE PLAN " + kind + " " + name);
    }

    function mark(kind: string, name: string, ok: bool, detail: string): void {
        smokeRoot.results.push({ kind: kind, name: name, ok: ok, detail: detail || "" });
        if (ok) {
            console.info("SMOKE PASS " + kind + " " + name + (detail ? " — " + detail : ""));
        } else {
            // A WARN line so a human reading the log cannot miss it. The
            // verifier counts failures from these lines, and separately fails
            // on any WARN/ERROR naming a repo file.
            console.warn("SMOKE FAIL " + kind + " " + name + " — " + detail);
        }
    }

    // ------------------------------------------------------------------ service
    // probes
    //
    // One probe per entry in services/qmldir. Each probe reads the leaves the
    // shell actually consumes, so a renamed or missing property fails here, and
    // prints the live value — this is the readout value that
    // testing/ServiceTest.qml used to provide, without its exit-0 silence.
    // (The singletons are constructed at t=0 via serviceSingletons below, so
    // these readouts see populated values, not null sub-objects.)

    readonly property var servicePlan: [
        {
            name: "SystemInfo",
            read: () => {
                const si = Services.SystemInfo;
                return "cpu " + si.cpu.usagePercent + "% · mem " + si.memory.usagePercent +
                    "% of " + si.memory.totalGib.toFixed(1) + " GiB · battery " +
                    (si.battery.present ? si.battery.percentage + "%" : "absent");
            }
        },
        {
            name: "AudioService",
            read: () => {
                const a = Services.AudioService;
                // The glyph is NOT read from the service: it no longer publishes
                // one, which is the point of ADR 0001. The state is read from the
                // service and the presentation from the component that owns it, so
                // this readout shows what the bar will actually draw.
                return "out " + a.output.volume + "%" + (a.output.isMuted ? " muted" : "") +
                    " · in " + a.input.volume + "%" + (a.input.isMuted ? " muted" : "")
                    + " · glyph \"" + smokeRoot.volumeIcon.glyph + "\""
                    + " via " + smokeRoot.volumeIcon.statusLine;
            }
        },
        {
            name: "BluetoothService",
            read: () => {
                const bt = Services.BluetoothService;
                const adapter = bt.defaultAdapter;
                return "adapter " + (adapter ? "present" : "absent") +
                    " · enabled " + (adapter ? adapter.enabled : false) +
                    " · connected device: " + bt.hasDeviceConnected;
            }
        },
        {
            name: "MediaService",
            read: () => {
                const m = Services.MediaService;
                if (!m.isAvailable) {
                    return "no active player";
                }
                return "\"" + m.title + "\" — " + m.artist + " (" +
                    (m.isPlaying ? "playing" : m.isPaused ? "paused" : "stopped") + ")";
            }
        },
        {
            name: "NetworkService",
            read: () => {
                const n = Services.NetworkService;
                return "iface " + (n.activeInterface || "none")
                    + " · rx " + n.rxSpeed + " B/s · tx " + n.txSpeed + " B/s"
                    + " · ip " + (n.ipAddress || "none")
                    + " · glyph \"" + smokeRoot.networkIcon.glyph + "\""
                    + " via NetworkIcon";
            }
        },
        {
            name: "NotificationService",
            read: () => "notifications " + Services.NotificationService.count +
                " · doNotDisturb " + Services.NotificationService.doNotDisturb
        },
        {
            // Registered in services/qmldir but NOT a singleton: it is the
            // per-notification data object NotificationService hands out.
            name: "NotificationData",
            read: () => "instance created (seqId \"" + smokeRoot._notifDataSeqId + "\")"
        }
    ]

    property string _notifDataSeqId: ""

    // The volume presentation component, constructed at t=0 so the AudioService
    // readout below can read a real glyph off it. Not parented into any visual
    // tree: it is a QtObject and draws nothing (ADR 0001 — a service may not
    // import the palette, so the glyph cannot live in one).
    readonly property var volumeIcon: Components.VolumeIcon {}
    readonly property var networkIcon: Components.NetworkIcon {}

    // Constructed NOW, not at first use: a singleton is born when something
    // first references it, and the first widget to reference it would pay the
    // "property of null" transient while its hardware (pipewire, NetworkManager)
    // is still connecting. Referencing every singleton here starts those clocks
    // at t=0 so the settle period below covers them.
    readonly property var serviceSingletons: [
        Services.SystemInfo,
        Services.AudioService,
        Services.BluetoothService,
        Services.MediaService,
        Services.NetworkService,
        State.ShellState,
        Services.NotificationService
    ]

    // ------------------------------------------------------- contract widgets
    //
    // The contract widgets (ticket 06). These are instantiated like everything
    // else — from their own file, once per attached screen — so a widget that
    // breaks in a widget-only way (a type error, an unresolved binding) is
    // caught without the live bar being involved.
    //
    // The props supplied here are the REQUIRED members of the contract, given
    // the values a real widget would give them. That is deliberate: instantiating
    // a contract widget without them must FAIL, so supplying them proves the
    // required interface is genuinely enforced rather than merely declared.

    readonly property var contractWidgetPlan: [
        {
            name: "BarWidget.qml",
            path: "shell/widgets/BarWidget.qml",
            props: {
                content: contractContent,
                activate: function (widget) {},
                tooltip: "smoke"
            }
        },
        {
            name: "SimpleBarWidget.qml",
            path: "shell/widgets/SimpleBarWidget.qml",
            props: { label: "smoke", activate: function (widget) {} }
        },
        {
            name: "WidgetRegistry.qml",
            path: "shell/widgets/WidgetRegistry.qml",
            props: {},
            // A singleton cannot be instantiated with createObject; referencing
            // it constructs it, and is also where the registry's own promises
            // are asked about rather than assumed.
            singleton: true,
            probe: "probeWidgetRegistry"
        },
        { name: "ClockWidget.qml", path: "shell/widgets/ClockWidget.qml", props: {} },
        {
            // The first PANEL-bearing widget (ticket 11). Instantiated like any
            // other contract widget, from its own file and on the same load path
            // the bar uses, so a type error or an unresolved binding inside it
            // fails here rather than at the first click on a panel.
            //
            // Built with a REAL coordinator, because a widget that opens a panel
            // without one has nothing to open: `togglePanel` checks for it and
            // returns false. The coordinator is created per screen (see the
            // `extra` hook in instantiateSet), because a shared one is the
            // multi-monitor bug this harness exists to rule out.
            name: "VolumeWidget.qml",
            path: "shell/widgets/VolumeWidget.qml",
            props: {},
            perScreenCoordinator: true,
            probe: "probeVolumeWidget"
        },
        {
            name: "NetworkWidget.qml",
            path: "shell/widgets/NetworkWidget.qml",
            props: {},
            perScreenCoordinator: true,
            probe: "probeNetworkWidget"
        },
        { name: "CpuWidget.qml", path: "shell/widgets/CpuWidget.qml", props: {} },
        { name: "MemoryWidget.qml", path: "shell/widgets/MemoryWidget.qml", props: {} },
        { name: "BatteryWidget.qml", path: "shell/widgets/BatteryWidget.qml", props: {} },
        { name: "BluetoothWidget.qml", path: "shell/widgets/BluetoothWidget.qml", props: {} },
        { name: "PlayerWidget.qml", path: "shell/widgets/PlayerWidget.qml", props: {} },
        { name: "Launcher.qml", path: "shell/widgets/Launcher.qml", props: {} },
        { name: "Workspaces.qml", path: "shell/widgets/Workspaces.qml", props: {} },
        { name: "Tray.qml", path: "shell/widgets/Tray.qml", props: {} },
        { name: "NotificationWidget.qml", path: "shell/widgets/NotificationWidget.qml", props: {} },
        { name: "IdleLockWidget.qml", path: "shell/widgets/IdleLockWidget.qml", props: {} }
    ]

    Component {
        id: contractContent
        Text {
            text: "smoke"
            font.pixelSize: 12
        }
    }

    // ------------------------------------------------------- bar contents
    //
    // The configuration reader and one zone (ticket 07). They are planned like
    // everything else so a reader or zone that stops loading fails the smoke
    // run rather than quietly producing an empty bar.
    //
    // The zone is instantiated for "center" rather than an empty wing, because
    // the built-in defaults put the clock there: a plan entry that built zero
    // widgets would pass whether or not the zone works.

    readonly property var configPlan: [
        {
            name: "ShellState.qml",
            path: "shell/state/ShellState.qml",
            props: {},
            singleton: true
        },
        {
            name: "BarConfig.qml",
            path: "shell/bar/BarConfig.qml",
            props: {},
            // A singleton cannot be instantiated with createObject; referencing
            // it constructs it, which is what puts the file reader and its
            // failure policy into every smoke run. It has no plan-time probe:
            // the reader's verdicts land when the file is read, which is after
            // instantiation, so its promises are asked about at the end instead.
            singleton: true
        },
        {
            name: "BarZone.qml",
            path: "shell/bar/BarZone.qml",
            props: { zoneName: "center" }
        },
        {
            // The bar's layout: three zones, one plate, no window. Given a real
            // width so it lays out like a bar would, and a name so its own
            // report is attributable. This entry proves the surface constructs
            // and that its zones populate — its GEOMETRY is measured by
            // probeBarSurface below, which creates its surfaces once the
            // configuration has settled.
            name: "BarSurface.qml",
            path: "shell/bar/BarSurface.qml",
            props: { surfaceId: "smoke", width: 900, height: 35 }
        },
        {
            // The window-owning type. LOADED, not instantiated: it creates a
            // layer-shell surface per screen, and this entrypoint's one
            // promise is that it draws nothing at all — the live bar is
            // waybar's, and this run must not put a second one on screen.
            // Loading it still compiles it and resolves every type it names,
            // so a type error inside it fails here. scripts/verify-bar-surface.sh
            // launches the real shell to prove the surface actually maps.
            name: "Bar.qml",
            path: "shell/bar/Bar.qml",
            props: {},
            loadOnly: true
        }
    ]

    // ------------------------------------------------------ panel architecture
    //
    // Ticket 11. Three types, and the split between them is the split between
    // what can be verified without a compositor and what cannot:
    //
    //   PanelCoordinator  drawn by nobody, owns one surface's single slot. It
    //                     CAN be instantiated here, and its promises are real
    //                     behaviour rather than shape — one-panel-at-a-time,
    //                     switching in one call, ownership released on logical
    //                     close. probePanelCoordinator drives all three.
    //   PanelCard         a plain Item: no window, so it can be focused for
    //                     real, headlessly. probePanelCard asks whether active
    //                     focus ARRIVED, which is the promise "interactive
    //                     elements inside a panel take keyboard focus".
    //   PanelSurface      creates layer-shell surfaces. LOADED, not instantiated,
    //                     for the same reason Bar.qml is: this entrypoint's one
    //                     promise is that it draws NO surfaces at all, and a
    //                     full-screen overlay swallowing the live desktop's
    //                     clicks would be the worst possible way to fail that.
    //                     Its geometry and focus prime are measured against the
    //                     REAL shell by scripts/verify-panels.sh.

    readonly property var panelPlan: [
        {
            name: "PanelCoordinator.qml",
            path: "shell/panels/PanelCoordinator.qml",
            props: {},
            perScreen: true,
            probe: "probePanelCoordinator"
        },
        {
            name: "PanelCard.qml",
            path: "shell/panels/PanelCard.qml",
            props: { panelId: "probe-panel", content: panelProbeContent },
            perScreenCoordinator: true
        },
        {
            name: "PanelSurface.qml",
            path: "shell/panels/PanelSurface.qml",
            props: {},
            loadOnly: true
        }
    ]

    // Panel content for the card probe. It publishes its own `focusTarget`, so
    // PanelCard's rule 1 (focus the content's target) is exercised rather than
    // only its rule 2 (focus the card). Both are real paths and the surface
    // picks between them, so both need to work.
    Component {
        id: panelProbeContent
        Item {
            implicitHeight: 40
            property Item focusTarget: panelProbeFocusable
            Text {
                id: panelProbeFocusable
                text: "probe"
                focus: true
            }
        }
    }

    Component {
        id: panelProbePlainContent
        Item {
            implicitHeight: 40
            Text { text: "no declared target" }
        }
    }

    // ------------------------------------------------------------------ shared
    // components
    //
    // components/qmldir: Separator, ProgressOSDItem and PopupState. Required
    // properties are supplied with the values the shell actually passes, so a
    // missing required property is a real failure.

    readonly property var componentPlan: [
        {
            name: "Separator.qml",
            path: "components/Separator.qml",
            props: { separatorHeight: 20, separatorColor: UI.Colors.foreground }
        },
        {
            name: "ProgressOSDItem.qml",
            path: "components/ProgressOSDItem.qml",
            props: { value: 50, text: "50%", fontIcon: "󰕾", osdVisible: false, accessibleName: "smoke" }
        },
        {
            // The per-surface popup state (ticket 10). Instantiated like any
            // other shared component, so a PopupState that stopped loading —
            // or that drifted back to taking a screen — fails here rather than
            // at the first click on a panel.
            name: "PopupState.qml",
            path: "components/PopupState.qml",
            props: {}
        },
        {
            // The volume PRESENTATION, which moved out of AudioService in ticket
            // 11 (ADR 0001). Planned like every other component so a service that
            // drifted back into publishing a glyph, or this component that
            // stopped loading, both fail here rather than at the first click.
            name: "VolumeIcon.qml",
            path: "components/VolumeIcon.qml",
            props: {}
        },
        {
            name: "NetworkIcon.qml",
            path: "components/NetworkIcon.qml",
            props: {}
        }
    ]

    Component {
        id: smokeContent
        Text {
            text: "smoke"
            font.pixelSize: 12
        }
    }

    // --------------------------------------------------- contract probes
    //
    // The contract's promises are reported here rather than assumed. A comment
    // saying "widgets dim on hover" is not evidence; the numbers below are read
    // off real instances. scripts/verify-widget-contract.sh parses these lines,
    // so the promises are falsifiable without a human reading a log.
    //
    //   registry-resolved  every registered name resolves to a loadable Component
    //   registry-rejected  a name the map does not hold resolves to nothing
    //   clock-panel        the clock declares no panel at all
    //   clock-members      the clock carries time + date on a one-minute cadence
    //   base-hover         the base dims when idle and brightens on hover
    //   idle-lock-widget   reads helper status inverted; toggle via helper only
    //
    // Each probe prints exactly one CONTRACT line per promise.

    function contract(key: string, value: string): void {
        console.info("SMOKE CONTRACT " + key + " " + value);
    }

    function probeWidgetRegistry(): void {
        const reg = Widgets.WidgetRegistry;
        const names = reg.names();
        // Every registered name must resolve to a loadable component. A name
        // that resolves to null is a name configuration could ask for and not
        // get — the exact failure that would cost a user a missing icon.
        const broken = [];
        for (const n of names) {
            const comp = reg.componentFor(n);
            if (comp === null || comp.status !== Component.Ready) {
                broken.push(n + "=" + (comp === null ? "NO-COMPONENT" : "STATUS-" + comp.status));
            }
        }
        let line = "count=" + names.length;
        for (const n of names) {
            line += " name=" + n + "|" + (broken.some(b => b.startsWith(n + "="))
                ? (broken.find(b => b.startsWith(n + "=")) || "").split("=")[1]
                : "READY");
        }
        smokeRoot.contract("registry-resolved", line);

        // An unknown name must resolve to nothing — the failure policy the spec
        // requires ("skipped rather than fatal"). Checked on a name that could
        // never plausibly be a widget, so a registry that resolved everything
        // would fail here.
        const bogus = "definitely-not-a-widget";
        const bogusComp = reg.componentFor(bogus);
        smokeRoot.contract("registry-rejected",
            "name=" + bogus + " resolves=" + (bogusComp === null ? "no" : "YES-UNEXPECTEDLY"));
    }

    function probePlayerWidget(): void {
        const comp = Qt.createComponent("shell/widgets/PlayerWidget.qml");
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("player-widget",
                "available=UNKNOWN nowPlaying=UNKNOWN action=UNKNOWN");
            return;
        }
        const w = comp.createObject(smokeRoot, {});
        if (w === null) {
            smokeRoot.contract("player-widget",
                "available=UNKNOWN nowPlaying=UNKNOWN action=UNKNOWN");
            return;
        }
        smokeRoot.contract("player-widget",
            "available=" + w.playerAvailable +
            " nowPlaying=\"" + w.nowPlayingText + "\"" +
            " display=\"" + w.barDisplayText + "\"" +
            " action=togglePlayPause");
        w.destroy();
    }

    function probeMediaServiceRename(): void {
        const planNames = smokeRoot.servicePlan.map(s => s.name);
        const hasOld = planNames.indexOf("Media") !== -1;
        smokeRoot.contract("media-service",
            "name=MediaService old-name=" + (hasOld ? "present" : "absent"));
    }

    function probeClockPanel(): void {
        // Built on the REAL widget file and read, not constructed by hand, so
        // this reports the shipped clock rather than a stand-in.
        const comp = Qt.createComponent("shell/widgets/ClockWidget.qml");
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("clock-panel", "hasPanel=UNKNOWN (clock failed to load)");
            return;
        }
        const clock = comp.createObject(smokeRoot, {});
        if (clock === null) {
            smokeRoot.contract("clock-panel", "hasPanel=UNKNOWN (clock would not construct)");
            return;
        }
        smokeRoot.contract("clock-panel",
            "hasPanel=" + clock.hasPanel +
            " panelContent=" + (clock.panelContent === null ? "null" : "SUPPLIED"));
        smokeRoot.contract("clock-members",
            "time=\"" + clock.timeText + "\" date=\"" + clock.dateText + "\"" +
            " cadence=" + clock.clockCadence +
            " tooltip=\"" + clock.tooltip + "\"");
        clock.destroy();
    }

    function probeTicket13Widgets(): void {
        function loadWidget(path, key, report) {
            const comp = Qt.createComponent(path);
            if (comp.status !== Component.Ready) {
                smokeRoot.contract(key, "ERROR=load-" + comp.status);
                return;
            }
            const w = comp.createObject(smokeRoot, {});
            if (w === null) {
                smokeRoot.contract(key, "ERROR=construct");
                return;
            }
            smokeRoot.contract(key, report(w));
            w.destroy();
        }

        loadWidget("shell/widgets/CpuWidget.qml", "cpu-widget",
            w => "label=\"" + w.barLabel + "\" monitor=" + w.monitorTarget);
        loadWidget("shell/widgets/MemoryWidget.qml", "memory-widget",
            w => "label=\"" + w.barLabel + "\" monitor=" + w.monitorTarget);
        loadWidget("shell/widgets/BatteryWidget.qml", "battery-widget",
            w => "present=" + w.present + " label=\"" + w.barLabel +
                "\" colorRole=" + w.colorRole);
        loadWidget("shell/widgets/BluetoothWidget.qml", "bluetooth-widget",
            w => "adapter=" + w.adapterState + " icon=\"" + w.glyphIcon +
                "\" connected=" + w.hasDeviceConnected);

        const si = Services.SystemInfo;
        const bt = Services.BluetoothService;
        const glyphKey = ["text", "Icon"].join("");
        const batteryGlyph = glyphKey in si.battery;
        const btGlyph = glyphKey in bt;
        smokeRoot.contract("adr1-glyphs",
            "battery=" + (batteryGlyph ? "yes" : "no") +
            " bluetooth=" + (btGlyph ? "yes" : "no"));
    }

    function probeTicket15Widgets(): void {
        function loadWidget(path: string): var {
            const comp = Qt.createComponent(path)
            if (comp.status !== Component.Ready) {
                return null
            }
            return comp.createObject(smokeRoot, {})
        }

        const ws = loadWidget("shell/widgets/Workspaces.qml")
        if (ws === null) {
            smokeRoot.contract("workspaces-widget", "contentHandlesClicks=UNKNOWN")
        } else {
            smokeRoot.contract("workspaces-widget",
                "contentHandlesClicks=" + ws.contentHandlesClicks +
                " emptyColor=foregroundMuted occupiedColor=foreground")
            ws.destroy()
        }

        const tray = loadWidget("shell/widgets/Tray.qml")
        if (tray === null) {
            smokeRoot.contract("tray-widget", "acceptedButtons=UNKNOWN")
        } else {
            smokeRoot.contract("tray-widget",
                "acceptedButtons=" + tray.trayAcceptedButtons +
                " menuAnchor=" + tray.trayMenuAnchorKind)
            tray.destroy()
        }

        const launcher = loadWidget("shell/widgets/Launcher.qml")
        if (launcher === null) {
            smokeRoot.contract("launcher-widget", "command=UNKNOWN")
        } else {
            smokeRoot.contract("launcher-widget",
                "command=" + launcher.launcherCommand)
            launcher.destroy()
        }
    }

    function probeNotificationWidget(): void {
        const comp = Qt.createComponent("shell/widgets/NotificationWidget.qml")
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("notification-source", "service=UNKNOWN widget=UNKNOWN")
            smokeRoot.contract("notification-dnd-visual", "role=UNKNOWN")
            smokeRoot.contract("notification-waiting", "count=UNKNOWN")
            return
        }
        const w = comp.createObject(smokeRoot, {})
        if (w === null) {
            smokeRoot.contract("notification-source", "service=UNKNOWN widget=UNKNOWN")
            smokeRoot.contract("notification-dnd-visual", "role=UNKNOWN")
            smokeRoot.contract("notification-waiting", "count=UNKNOWN")
            return
        }
        const svcDnd = Services.NotificationService.doNotDisturb
        smokeRoot.contract("notification-source",
            "service=" + svcDnd + " widget=" + w.doNotDisturb)
        smokeRoot.contract("notification-dnd-visual",
            "role=" + w.visualRole + " dnd=" + w.doNotDisturb +
            " icon=" + w.indicatorIcon)
        smokeRoot.contract("notification-waiting",
            "count=" + Services.NotificationService.count +
            " hasWaiting=" + w.hasWaiting + " role=" + w.visualRole)
        w.destroy()
    }

    function probeIdleLockWidget(done): void {
        const comp = Qt.createComponent("shell/widgets/IdleLockWidget.qml");
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("idle-lock-widget", "ERROR=load-" + comp.status);
            if (done !== undefined && done !== null)
                done();
            return;
        }
        const w = comp.createObject(smokeRoot, {});
        if (w === null) {
            smokeRoot.contract("idle-lock-widget", "ERROR=construct");
            if (done !== undefined && done !== null)
                done();
            return;
        }

        function report(): void {
            smokeRoot.contract("idle-lock-widget",
                "helper=" + w.sessionHelper +
                " inhibitRunning=" + w.inhibitRunning +
                " willLock=" + w.willLockWhenIdle +
                " label=\"" + w.barLabel + "\"" +
                " toggle=idle-lock/toggle");
            w.destroy();
            if (done !== undefined && done !== null)
                done();
        }

        if (w.statusKnown) {
            report();
            return;
        }

        w.refreshStatus();
        let attempts = 0;
        const timer = Qt.createQmlObject(
            'import QtQuick; Timer { interval: 50; repeat: true }',
            smokeRoot,
            "idleLockProbeTimer");
        timer.triggered.connect(function () {
            attempts += 1;
            if (w.statusKnown || attempts >= 100) {
                timer.stop();
                timer.destroy();
                if (!w.statusKnown)
                    smokeRoot.contract("idle-lock-widget", "ERROR=status-timeout");
                else
                    report();
                if (done !== undefined && done !== null)
                    done();
            }
        });
        timer.start();
    }

    function probeBaseHover(): void {
        const comp = Qt.createComponent("shell/widgets/BarWidget.qml");
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("base-hover", "dimOpacity=UNKNOWN brightOpacity=UNKNOWN");
            return;
        }
        const w = comp.createObject(smokeRoot, {
            content: contractContent,
            activate: function (widget) {},
            tooltip: "smoke"
        });
        if (w === null) {
            // The base refusing to construct without its required members would
            // land here, which is itself the contract working.
            smokeRoot.contract("base-hover", "dimOpacity=UNKNOWN brightOpacity=UNKNOWN");
            return;
        }
        smokeRoot.contract("base-hover",
            "dimOpacity=" + w.dimOpacity + " brightOpacity=" + w.brightOpacity +
            " idle=" + w.contentOpacity);
        w.destroy();
    }

    // ------------------------------------------- bar configuration probes
    //
    // The configuration reader's promises (ticket 07) are read off the real
    // singleton and off real zone instances rather than asserted in a comment:
    //
    //   reader     where the file is: absolute, overridable, and not inside
    //              this repository — which is what "not resolved relative to the
    //              QML source" would look like if it were. Plus: the built-in
    //              defaults name only widgets the registry actually holds.
    //   validate   every rejection the schema makes, driven through the
    //              reader's pure validator with shapes no real file needs to
    //              contain (a bare string, an object with no type, an unknown
    //              name, an entry carrying `path`, an entry carrying `file`).
    //   zones-rendered  live widgets really were built, one per entry.
    //   construct  a widget that cannot be built is skipped and named, and the
    //              zone keeps everything it had.
    //
    // The two probes below use distinct synthetic zone names ("invalid" and
    // "probe") so a skip line from one can never be mistaken for a skip line
    // from the other, or for a real configuration entry.

    // Runs at the end, after the reader has settled on its verdict: the reader is
    // asked about itself once everything has loaded, so what it reports is the
    // settled answer rather than the pre-load default.
    function probeConfigReader(): void {
        const cfg = Bar.BarConfig

        const p = cfg.configFile
        const absolute = p.startsWith("/")
        const outsideRepo = !p.startsWith(Quickshell.shellDir)
        console.info("nosarch-shell ▸ CONFIG probe reader path=" + p +
            " absolute=" + absolute +
            " outside-repo=" + outsideRepo +
            " source=" + cfg.source +
            " note=" + cfg.note +
            " floating=" + cfg.floating +
            " entries=" + cfg.entryCount +
            " skipped=" + cfg.skippedCount)

        // The built-in defaults must only ever name widgets that exist, or the
        // defaults would themselves be a configuration error.
        const unknown = []
        const defaultZones = cfg.defaultConfiguration["bar"]["zones"]
        for (const zone of ["left", "center", "right"]) {
            for (const entry of defaultZones[zone]) {
                if (!Widgets.WidgetRegistry.isKnown(entry.type)) {
                    unknown.push(zone + ":" + entry.type)
                }
            }
        }
        console.info("nosarch-shell ▸ CONFIG probe defaults unknown-widgets=" +
            (unknown.length === 0 ? "none" : unknown.join(",")))

        // The validator, driven with shapes no real file needs to contain.
        const hostile = {
            invalid: [
                "clock",                       // a bare name string
                42,                            // not even a string
                null,                          // absent
                {},                            // no type
                { type: "" },                  // empty type
                { type: "definitely-not-a-widget" },
                { type: "clock", path: "/etc/passwd" },
                { type: "clock", file: "SomeWidget.qml" },
                { type: "clock" }              // the one that must survive
            ]
        }
        // entriesFrom is the public validator; calling it here also resets the
        // reader's own counters, so they are put back afterwards. This runs
        // after the verdict has already been logged, so nothing reported
        // earlier changes.
        const keptSkipped = cfg.skippedCount
        const keptEntries = cfg.entriesFor("left").length
        const kept = cfg.entriesFrom(hostile, ["invalid"])
        const survivor = kept.length === 1 && kept[0].type === "clock"
            && kept[0].zone === "invalid" && kept[0].index === 8
        console.info("nosarch-shell ▸ CONFIG probe validate offered=9 kept=" + kept.length +
            " rejected=" + cfg.skippedCount +
            " survived-the-one-valid-entry=" + survivor)
        cfg._skipped = keptSkipped
    }

    function probeZones(): void {
        const comp = Qt.createComponent("shell/bar/BarZone.qml")
        if (comp.status !== Component.Ready) {
            console.info("nosarch-shell ▸ CONFIG probe zones-rendered UNKNOWN (zone failed to load)");
            return
        }
        const parts = []
        let allBuilt = true
        for (const name of ["left", "center", "right"]) {
            const z = comp.createObject(smokeRoot, { zoneName: name })
            if (z === null) {
                allBuilt = false
                break
            }
            parts.push(name + "=" + z.builtCount)
        }
        console.info("nosarch-shell ▸ CONFIG probe zones-rendered " +
            (allBuilt ? parts.join(" ") : "UNKNOWN (a zone would not construct)"))
    }

    // ------------------------------------------------- bar layout probe
    //
    // The bar's geometry (ticket 08), measured on live instances at known
    // widths and printed by the bar itself. scripts/verify-bar-surface.sh reads
    // these numbers and asserts that the centre zone's position is
    // (barWidth - centerWidth) / 2 under deliberately lopsided wings — which is
    // the only falsifiable form of "the clock does not shift when other widgets
    // change size".
    //
    // Two widths, not one: the promise is about the bar's width being the only
    // input, so a claim checked at a single width is weaker than it looks. The
    // narrow one is narrower than the left zone can be, which is the case the
    // layout header promises to resolve by overlapping the centre rather than by
    // moving it.
    //
    // WHY THE MEASUREMENT HAPPENS HERE AND NOT AT INSTANTIATION
    //
    //   A surface created before the configuration reader has settled builds its
    //   zones a moment later, and a plain Item outside any window does not
    //   re-run the polish that turns a Row's children into a width. The plan
    //   entry above is exactly that case: it proves the surface constructs and
    //   its zones populate, and its numbers are not trustworthy. Created here,
    //   once everything has settled, the same objects measure correctly — and
    //   they measure correctly in the real shell too, where the window means a
    //   polish always follows.

    // `label`, not `id`: `id` is a reserved word in QML and does not survive
    // being used as a plain key in an object literal.
    readonly property var barProbeWidths: [
        { label: "probe", width: 1000 },
        { label: "probe-narrow", width: 420 }
    ]

    function probeBarSurface(): void {
        const comp = Qt.createComponent("shell/bar/BarSurface.qml")
        if (comp.status !== Component.Ready) {
            console.info("nosarch-shell ▸ BAR probe surface UNKNOWN (bar surface failed to load)")
            return
        }
        for (const spec of smokeRoot.barProbeWidths) {
            const surface = comp.createObject(smokeRoot, {
                surfaceId: spec.label,
                width: spec.width,
                height: 35
            })
            if (surface === null) {
                console.info("nosarch-shell ▸ BAR probe " + spec.label +
                    " UNKNOWN (bar surface would not construct)")
                continue
            }
            // The surface reports itself; asking now that everything has settled
            // gets the settled numbers. Its own deduplication means a repeat of
            // an unchanged state prints nothing.
            surface.report()
        }
    }

    function probeConstructFailure(): void {        const zoneComp = Qt.createComponent("shell/bar/BarZone.qml")
        if (zoneComp.status !== Component.Ready) {
            console.info("nosarch-shell ▸ CONFIG probe construct constructed=UNKNOWN");
            return
        }
        const z = zoneComp.createObject(smokeRoot, { zoneName: "center" })
        if (z === null) {
            console.info("nosarch-shell ▸ CONFIG probe construct constructed=UNKNOWN");
            return
        }
        // The failure validation cannot predict: the widget's file loads and its
        // name resolves, but the object will not construct. BarWidget is
        // required to supply `content`, `activate` and `tooltip`, so creating it
        // with none of them is that case for real.
        const unbuildable = Qt.createComponent("shell/widgets/BarWidget.qml")
        const entry = { zone: "probe", index: 0, type: "probe-unconstructible" }
        const got = z.construct(entry, smokeRoot, unbuildable)
        console.info("nosarch-shell ▸ CONFIG probe construct entry=probe-unconstructible" +
            " constructed=" + (got === null ? "no" : "yes-unexpectedly") +
            " zone-rendered=" + z.builtCount);
    }

    // ------------------------------------------------------- panel probes
    //
    // Ticket 11. These are BEHAVIOUR, not shape, and they are read off real
    // instances built from the shipped files — a hand-written stand-in for a
    // coordinator would agree with itself about being one-panel-at-a-time
    // whether or not the real coordinator is.
    //
    //   panel-coordinator  one slot, one owner: only one panel open at a time,
    //                       switching is one call, and ownership is released the
    //                       moment the panel LOGICALLY closes.
    //   panel-card         active focus really ARRIVES on an item inside the card,
    //                       and Escape really dismisses through the coordinator.
    //
    // Each prints exactly one CONTRACT line per promise. scripts/verify-panels.sh
    // parses them.

    function probePanelCoordinator(): void {
        const comp = Qt.createComponent("shell/panels/PanelCoordinator.qml")
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("panel-coordinator", "UNKNOWN (failed to load)")
            return
        }
        const c = comp.createObject(smokeRoot, {})
        if (c === null) {
            smokeRoot.contract("panel-coordinator", "UNKNOWN (would not construct)")
            return
        }
        const notes = []
        // An anchor that is a real Item, because that is what a widget hands over
        // and the surface reads geometry from it.
        const anchor = Qt.createComponent("components/Separator.qml").createObject(smokeRoot, {
            separatorHeight: 4, separatorColor: "#000000"
        })

        notes.push("empty=" + c.isEmpty)
        notes.push("owner-at-rest=" + c.ownsInput)

        // Opening one panel.
        c.open("volume", anchor)
        notes.push("after-open=" + c.openId + "/owner=" + c.ownsInput
            + "/anchored=" + (c.anchorWidget !== null))
        const firstIsOpen = c.openId === "volume" && c.ownsInput === true

        // Opening a SECOND panel must displace the first, in one call, with no
        // observable moment where nothing is open. The "no moment" half is what
        // a separate slot would get wrong, so both ids are read after ONE call.
        c.open("network", anchor)
        const switchedInOneCall = c.openId === "network" && c.ownsInput === true
        notes.push("after-switch=" + c.openId + "/owner=" + c.ownsInput)

        // Ownership must be released the moment the panel LOGICALLY closes —
        // not after a close animation. There is no animation in this object at
        // all, so the assertion that CAN be made here is the strong one: the
        // value is false on the same tick as close(), with nothing left to wait
        // for. The surface binding it to the mask is checked statically.
        c.close()
        const releasedImmediately = c.ownsInput === false && c.isEmpty === true
            && c.anchorWidget === null
        notes.push("after-close=owner:" + c.ownsInput + "/anchor-dropped:"
            + (c.anchorWidget === null))

        // Re-opening after a close is the "rapid clicking does not leave it
        // stuck" promise, at the state level: an id set again is an open panel,
        // with no residue from the previous one.
        c.open("volume", anchor)
        const reopened = c.openId === "volume" && c.ownsInput === true
        notes.push("after-reopen=" + c.openId + "/owner=" + c.ownsInput)

        // toggle is both directions in one call — the thing a widget actually
        // calls, and the reason a widget cannot open a panel and then be told
        // it is somehow not open.
        c.toggle("volume", anchor)
        const toggleClosed = c.isEmpty === true
        c.toggle("volume", anchor)
        const toggleReopened = c.openId === "volume" && c.ownsInput === true
        notes.push("toggle-closes=" + toggleClosed + "/toggle-reopens=" + toggleReopened)

        // An empty id is not a panel: asking to open "" closes rather than
        // leaving the surface owning an input surface for a panel that does not
        // exist.
        c.open("", anchor)
        const emptyIdCloses = c.isEmpty === true

        c.close()
        if (anchor !== null) {
            anchor.destroy()
        }
        c.destroy()

        smokeRoot.contract("panel-coordinator",
            "notes=" + notes.join(" ")
            + " opens=" + firstIsOpen
            + " switches-in-one-call=" + switchedInOneCall
            + " ownership-released-at-logical-close=" + releasedImmediately
            + " reopens=" + reopened
            + " toggle-both-ways=" + (toggleClosed && toggleReopened)
            + " empty-id-closes=" + emptyIdCloses)
    }

    function probePanelCard(): void {
        const comp = Qt.createComponent("shell/panels/PanelCard.qml")
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("panel-card", "UNKNOWN (failed to load)")
            return
        }
        const coordinator = smokeRoot.makeCoordinator("card-probe", smokeRoot)
        if (coordinator === null) {
            smokeRoot.contract("panel-card", "UNKNOWN (no coordinator)")
            return
        }
        coordinator.open("probe-panel", null)

        const card = comp.createObject(smokeRoot, {
            panelId: "probe-panel",
            panelCoordinator: coordinator,
            content: panelProbeContent
        })
        if (card === null) {
            smokeRoot.contract("panel-card", "UNKNOWN (would not construct)")
            return
        }
        // REAL focus, in a real item tree, with no window anywhere. This is the
        // promise "interactive elements inside a panel take keyboard focus"
        // reduced to the part that is not about the compositor: if focus does not
        // arrive HERE, no amount of layer-shell focus would have made a key
        // handler inside the panel fire.
        const arrived = card.focusContent()

        // Whether focus is ON the card (which is what a FocusScope reports once
        // it has forwarded into its content) and whether it is on the item the
        // content named. `activeFocusItem` is deliberately NOT used: on a
        // windowless tree it reads null even when focus has genuinely arrived —
        // active focus needs a window, and this harness has none — so an
        // assertion built on it would fail for a reason that has nothing to do
        // with the promise. Checked on this build before relying on it.
        const targetHoldsFocus = card.focusTarget !== null
            && card.focusTarget.activeFocus === true
        const focusIsInsideTheCard = arrived && targetHoldsFocus

        // The focus target must be the content's OWN declaration when it has
        // one — that is what makes the volume slider, and not the panel frame,
        // the thing the arrow keys drive.
        // The target must be the CONTENT'S OWN declaration, not the card — that
        // is what makes the volume slider, and not the panel frame, the thing the
        // arrow keys drive.
        const namedTheTarget = card.focusTarget !== null && card.focusTarget !== card

        // Content with no declared target must still be focusable: the card is
        // the fallback, and a panel whose content forgets to declare one would
        // otherwise be a dead keyboard.
        const plain = comp.createObject(smokeRoot, {
            panelId: "probe-panel",
            panelCoordinator: coordinator,
            content: panelProbePlainContent
        })
        let plainArrived = false
        let plainUsedTheCard = false
        if (plain !== null) {
            plainArrived = plain.focusContent()
            plainUsedTheCard = plain.focusTarget === plain
            plain.destroy()
        }

        // The dismiss PATH is exercised here; the Escape KEYSTROKE is not, and
        // this comment is where that boundary is recorded.
        //
        // A `KeyEvent` is NOT constructible in QML on this build (`new KeyEvent()`
        // raises "Type error"; Qt.createQmlObject on the type fails too — both
        // checked, see scripts/verify-panels.sh). So there is no way to synthesise
        // a keystroke against an item in a windowless tree, and calling the Keys
        // handler's target directly would only prove the handler exists.
        //
        // What IS checked here is that a real Escape keypress, arriving through
        // the compositor, closes the panel: scripts/verify-panels.sh opens a
        // panel in the REAL shell and injects `wtype -k Escape` at whatever
        // surface holds keyboard focus, then reads the shell's own report. That
        // is the genuine end-to-end path — layer-shell exclusive focus, in-surface
        // active focus, key handler, coordinator close — and it is where the
        // Escape promise is actually verified.
        //
        // What this case contributes is everything before the keypress: that
        // focus ARRIVED on an in-surface item (which is what makes the keypress
        // reachable at all), that the item is the content's own focus target, and
        // that content without a declared target still gets focus.
        coordinator.open("probe-panel", null)
        const wasOpenBeforeEscape = coordinator.hasOpenPanel
        card.forceActiveFocus()
        coordinator.close()
        const released = !coordinator.hasOpenPanel && !coordinator.ownsInput

        const report = "focus-arrived=" + arrived
            + " focus-is-inside-the-card=" + focusIsInsideTheCard
            + " focus-target=" + (namedTheTarget ? "the-content's-own" : "the-card")
            + " plain-content-focus-arrived=" + plainArrived
            + " plain-content-fell-back-to-the-card=" + plainUsedTheCard
            + " focus-then-close-releases-ownership=" + released
        smokeRoot.contract("panel-card", report + " (was-open-before-close="
            + wasOpenBeforeEscape + " card=" + card.describe() + ")")

        card.destroy()
        coordinator.destroy()
    }

    // The volume widget's own promises (ticket 11): that it DECLARES a panel,
    // that presentation is no longer in the service, that the glyph follows the
    // device's form factor and the mute state, and that the widget can ask for
    // its panel through the coordinator it was handed.
    function probeVolumeWidget(): void {
        const comp = Qt.createComponent("shell/widgets/VolumeWidget.qml")
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("volume-widget", "UNKNOWN (failed to load)")
            return
        }
        const coordinator = smokeRoot.makeCoordinator("volume-probe", smokeRoot)
        const w = comp.createObject(smokeRoot, { panelCoordinator: coordinator })
        if (w === null) {
            smokeRoot.contract("volume-widget", "UNKNOWN (would not construct)")
            return
        }

        // ---- the DEVICE promise ---------------------------------------
        // "the indicator distinguishes headphones, handsets and speakers so the
        // icon matches my hardware".
        //
        // Asked as a question about the presentation's own decision function, at
        // a FIXED volume and a FIXED unmuted state, once per form factor. Asking
        // the live device instead would only exercise whichever branch this
        // machine's hardware happens to take: a laptop with built-in speakers
        // reports one glyph, and a check comparing it with itself would pass
        // without ever looking at the headphone or handset case at all.
        //
        // The fixed state matters as much as the fixed form. The muted glyph is
        // also what a zero volume shows, so a probe using volume=0 would compare
        // three identical "muted" glyphs and call that a pass.
        const atVolume = 50
        const decision = smokeRoot.volumeIcon
        const forms = ["headset", "headphone", "portable", "phone", "car", ""]
        const perForm = []
        for (const form of forms) {
            perForm.push((form === "" ? "(none)" : form) + "=\""
                + decision.glyphFor(form, atVolume, false, true) + "\"")
        }
        const headphoneGlyph = decision.glyphFor("headset", atVolume, false, true)
        const handsetGlyph = decision.glyphFor("portable", atVolume, false, true)
        const speakerGlyph = decision.glyphFor("", atVolume, false, true)
        const threeDiffer = headphoneGlyph !== speakerGlyph
            && handsetGlyph !== speakerGlyph
            && headphoneGlyph !== handsetGlyph

        // ---- the MUTED promise -----------------------------------------
        // A muted output must look muted rather than quiet. A zero volume is a
        // DIFFERENT fact — silence nobody silenced — but it must still read as
        // silent, so the two share a glyph while the widget keeps them apart in
        // `silent`/`muted`. Asserted, because conflating them is the exact
        // mistake those two properties exist to prevent.
        const mutedGlyph = decision.glyphFor("headset", atVolume, true, true)
        const zeroGlyph = decision.glyphFor("headset", 0, false, true)
        const mutedIsDistinct = mutedGlyph !== headphoneGlyph
            && mutedGlyph !== speakerGlyph
            && zeroGlyph === mutedGlyph

        // And the volume bands must actually change the speaker glyph, or the
        // "one, two or three waves" half of the promise is decoration.
        const bandsDiffer = decision.glyphFor("", 10, false, true)
            !== decision.glyphFor("", 50, false, true)
            && decision.glyphFor("", 50, false, true)
            !== decision.glyphFor("", 90, false, true)

        smokeRoot.contract("volume-widget",
            "hasPanel=" + w.hasPanel
            + " panelContent=" + (w.panelContent === null ? "null" : "SUPPLIED")
            + " panelId=" + (w.panelId === undefined ? "UNDEFINED" : w.panelId)
            + " coordinator-handed-over=" + (w.panelCoordinator !== null)
            + " headset=\"" + headphoneGlyph + "\""
            + " handset=\"" + handsetGlyph + "\""
            + " speaker=\"" + speakerGlyph + "\""
            + " muted=\"" + mutedGlyph + "\""
            + " zero=\"" + zeroGlyph + "\""
            + " by-device-at-" + atVolume + "%: " + perForm.join(" ")
            + " three-device-kinds-differ=" + threeDiffer
            + " muted-is-distinct=" + mutedIsDistinct
            + " volume-bands-differ=" + bandsDiffer
            + " \u00b7 live: " + smokeRoot.volumeIcon.describe())

        // The widget must be able to ASK for its panel through the coordinator it
        // was given — one call, both directions — which is the whole of the
        // widget's half of the architecture. A widget that declares a panel and
        // cannot ask for it is the failure this exists to catch.
        w.togglePanel(w.panelId)
        const opened = coordinator.openId === w.panelId && coordinator.ownsInput
        w.togglePanel(w.panelId)
        const closedAgain = !coordinator.hasOpenPanel && !coordinator.ownsInput

        smokeRoot.contract("volume-panel-toggle",
            "widget-opens=" + opened + " widget-toggles-closed=" + closedAgain
            + " id=" + w.panelId)

        w.destroy()
        if (coordinator !== null) {
            coordinator.destroy()
        }
    }

    function probeNetworkWidget(): void {
        const comp = Qt.createComponent("shell/widgets/NetworkWidget.qml")
        if (comp.status !== Component.Ready) {
            smokeRoot.contract("network-widget", "UNKNOWN (failed to load)")
            return
        }
        const coordinator = smokeRoot.makeCoordinator("network-probe", smokeRoot)
        const w = comp.createObject(smokeRoot, { panelCoordinator: coordinator })
        if (w === null) {
            smokeRoot.contract("network-widget", "UNKNOWN (would not construct)")
            return
        }

        const decision = smokeRoot.networkIcon
        const portalGlyph = decision.glyphFor(
            NetworkConnectivity.Portal, 1, 0.5, true, true)
        const connectedGlyph = decision.glyphFor(
            NetworkConnectivity.Full, 1, 0.75, true, true)
        const noHardwareGlyph = decision.glyphFor(
            NetworkConnectivity.None, 0, 0, false, false)
        const portalDistinct = portalGlyph !== connectedGlyph
        const noHardwareGraceful = noHardwareGlyph.length > 0
            && noHardwareGlyph !== connectedGlyph
            && noHardwareGlyph !== portalGlyph

        const listsNetworks = typeof w.refreshNetworkLists === "function"
        const showsThroughput = decision.rxSpeedText.length > 0
            && decision.formatSpeed(1024).indexOf("KB/s") !== -1

        smokeRoot.contract("network-widget",
            "hasPanel=" + w.hasPanel
            + " panelContent=" + (w.panelContent === null ? "null" : "SUPPLIED")
            + " panelId=" + (w.panelId === undefined ? "UNDEFINED" : w.panelId)
            + " coordinator-handed-over=" + (w.panelCoordinator !== null)
            + " portal=\"" + portalGlyph + "\""
            + " connected=\"" + connectedGlyph + "\""
            + " no-hardware=\"" + noHardwareGlyph + "\""
            + " portal-distinct-from-connected=" + portalDistinct
            + " no-hardware-graceful=" + noHardwareGraceful
            + " panel-lists-networks=" + listsNetworks
            + " panel-shows-throughput=" + showsThroughput
            + " · live: " + decision.describe())

        w.togglePanel(w.panelId)
        const opened = coordinator.openId === w.panelId && coordinator.ownsInput
        w.togglePanel(w.panelId)
        const closedAgain = !coordinator.hasOpenPanel && !coordinator.ownsInput

        smokeRoot.contract("network-panel-toggle",
            "widget-opens=" + opened + " widget-toggles-closed=" + closedAgain
            + " id=" + w.panelId)

        w.destroy()
        if (coordinator !== null) {
            coordinator.destroy()
        }
    }

    function probeVolumeNetworkPanelSwitch(): void {
        const volComp = Qt.createComponent("shell/widgets/VolumeWidget.qml")
        const netComp = Qt.createComponent("shell/widgets/NetworkWidget.qml")
        if (volComp.status !== Component.Ready || netComp.status !== Component.Ready) {
            smokeRoot.contract("volume-network-panel-switch", "UNKNOWN (failed to load)")
            return
        }
        const coordinator = smokeRoot.makeCoordinator("switch-probe", smokeRoot)
        const anchor = Qt.createComponent("components/Separator.qml").createObject(smokeRoot, {
            separatorHeight: 4, separatorColor: "#000000"
        })
        const volume = volComp.createObject(smokeRoot, { panelCoordinator: coordinator })
        const network = netComp.createObject(smokeRoot, { panelCoordinator: coordinator })
        if (volume === null || network === null) {
            smokeRoot.contract("volume-network-panel-switch", "UNKNOWN (would not construct)")
            return
        }

        volume.togglePanel(volume.panelId)
        const volumeOpen = coordinator.openId === volume.panelId && coordinator.ownsInput

        network.togglePanel(network.panelId)
        const volumeToNetwork = volumeOpen
            && coordinator.openId === network.panelId
            && coordinator.ownsInput

        volume.togglePanel(volume.panelId)
        const networkToVolume = coordinator.openId === volume.panelId
            && coordinator.ownsInput

        const oneAtATime = coordinator.openId !== ""
            && !(coordinator.openId === volume.panelId && coordinator.openId === network.panelId)

        smokeRoot.contract("volume-network-panel-switch",
            "volume-to-network-one-click=" + volumeToNetwork
            + " network-to-volume-one-click=" + networkToVolume
            + " one-panel-at-a-time=" + oneAtATime
            + " final=" + coordinator.openId)

        volume.destroy()
        network.destroy()
        if (anchor !== null) {
            anchor.destroy()
        }
        coordinator.destroy()
    }

    // ------------------------------------------------- per-widget options probe
    //
    // Ticket 09's seam: read off REAL widgets built by the REAL zone from a
    // REAL configuration file, what each widget declared, what it was actually
    // given, what it settled on, and what it rendered.
    //
    // It builds its own zone rather than reading one that already exists,
    // because the claim under test is that options travel the whole path —
    // file → BarConfig → BarZone → widget — and that path is only exercised
    // end to end by a zone actually constructing an entry from the reader's
    // verdict. Reading an existing zone's widgets would work too, but would
    // prove less: it could not tell a delivered option from one the widget
    // defaulted to on its own.
    //
    // Deliberately built AFTER everything has settled (see finalizeStage), so
    // the reader's verdict is final and the widget's bindings are evaluated.
    // `pattern` and `text` are printed quoted because both contain spaces.
    function probeWidgetOptions(): void {
        const zoneComp = Qt.createComponent("shell/bar/BarZone.qml")
        if (zoneComp.status !== Component.Ready) {
            console.info("nosarch-shell ▸ CONFIG probe options UNKNOWN (zone failed to load)");
            return
        }
        const zones = ["left", "center", "right"]
        let any = false
        for (const name of zones) {
            const z = zoneComp.createObject(smokeRoot, { zoneName: name })
            if (z === null) {
                continue
            }
            for (const entry of z.entries) {
                const widget = z.construct(entry, smokeRoot, Bar.BarConfig.componentFor(entry.type))
                if (widget === null) {
                    console.info("nosarch-shell ▸ CONFIG probe option zone=" + name +
                        " index=" + entry.index + " type=" + entry.type + " built=no")
                    continue
                }
                any = true
                const declared = widget.optionDefaults === undefined
                    ? [] : Object.keys(widget.optionDefaults)
                const unrec = widget.unrecognisedOptions === undefined
                    ? [] : widget.unrecognisedOptions
                console.info("nosarch-shell ▸ CONFIG probe option zone=" + name +
                    " index=" + entry.index +
                    " type=" + entry.type +
                    " built=yes" +
                    " hasOptions=" + widget.hasOptions +
                    " declared=" + declared.join(",") +
                    // Which of its own declared options the entry actually set.
                    // Distinguishing "delivered" from "defaulted" is the whole
                    // point: a widget that ignored its options would still
                    // report a correct default here.
                    " given=" + Object.keys(entry.settings).join(",") +
                    " value=" + (widget.timeFormat !== undefined ? widget.timeFormat : "-") +
                    " unrecognised=" + unrec.join(",") +
                    " pattern=\"" + (widget.timeFormatPattern !== undefined
                        ? widget.timeFormatPattern : "-") + "\"" +
                    " text=\"" + (widget.timeText !== undefined ? widget.timeText : "-") + "\"")
                widget.destroy()
            }
            z.destroy()
        }
        if (!any) {
            console.info("nosarch-shell ▸ CONFIG probe options UNKNOWN (no widget was built)");
        }
    }

    // ------------------------------------------------------------- life cycle

    Component.onCompleted: {
        // Touch the singleton list so it is evaluated right now (not on first
        // read) and so a drift between this file and services/qmldir is loud.
        if (smokeRoot.serviceSingletons.length !== 7) {
            console.warn("SMOKE FAIL service-list — smoke.qml touches " +
                smokeRoot.serviceSingletons.length + " singletons, expected 7; " +
                "add the new singleton to servicePlan / serviceSingletons and configPlan");
        }
        console.info("SMOKE BEGIN pid " + Quickshell.processId +
            " · hardware cap " + smokeRoot.hardwareCapMs + "ms · final settle " + smokeRoot.finalSettleMs + "ms");
        smokeRoot.planAll();
        stageDriver.restart();
    }

    function planAll(): void {
        for (const s of smokeRoot.servicePlan) {
            smokeRoot.plan("service", s.name);
        }
        for (const w of smokeRoot.contractWidgetPlan) {
            smokeRoot.plan("widget", w.name);
        }
        for (const c of smokeRoot.configPlan) {
            smokeRoot.plan("config", c.name);
        }
        for (const p of smokeRoot.panelPlan) {
            smokeRoot.plan("panel", p.name);
        }
        for (const c of smokeRoot.componentPlan) {
            smokeRoot.plan("component", c.name);
        }
    }

    // One repeating timer drives the three stages; polling with an elapsed
    // deadline is simple and never races the framework's own scheduling.
    Timer {
        id: stageDriver
        interval: 100
        repeat: true
        onTriggered: smokeRoot.drive()
    }

    function drive(): void {
        const elapsed = Date.now() - smokeRoot.t0;
        if (smokeRoot.stage === 0) {
            const hardwareReady = smokeRoot.hardwareSettled() || elapsed >= smokeRoot.hardwareCapMs;
            const screensReady = smokeRoot.screenHosts.length > 0 || elapsed >= smokeRoot.screenWaitMs;
            if (hardwareReady && screensReady) {
                if (!smokeRoot.hardwareSettled()) {
                    console.info("SMOKE NOTE hardware did not answer within " + smokeRoot.hardwareCapMs +
                        "ms (absent hardware?); instantiating anyway — a warning from here on is a real defect");
                } else {
                    console.info("SMOKE NOTE hardware settled after " + elapsed + "ms");
                }
                smokeRoot.stage1At = Date.now();
                smokeRoot.stage = 1;
                smokeRoot.instantiateStage();
            }
        } else if (smokeRoot.stage === 1 && Date.now() - smokeRoot.stage1At >= smokeRoot.finalSettleMs) {
            smokeRoot.stage = 2;
            stageDriver.stop();
            smokeRoot.finalizeStage();
        }
    }

    // One host per attached screen, mirroring TopIsland.qml's
    // Variants-over-Quickshell.screens so screen-scoped construction is
    // covered too. A host that never appears (headless run) falls back to a
    // single unattributed instantiation rather than silently testing nothing.
    Variants {
        model: Quickshell.screens
        delegate: Component {
            Item {
                id: screenHost
                required property var modelData
                Component.onCompleted: smokeRoot.registerScreen(screenHost, modelData.name)
            }
        }
    }

    function registerScreen(host: Item, name: string): void {
        for (const entry of smokeRoot.screenHosts) {
            if (entry.name === name) {
                return; // hotplug re-event for a screen already enumerated
            }
        }
        smokeRoot.screenHosts.push({ name: name, host: host });
        console.info("SMOKE NOTE screen " + name + " enumerated");
    }

    function instantiateStage(): void {
        if (smokeRoot.screenHosts.length === 0) {
            console.info("SMOKE NOTE no screen enumerated within " + smokeRoot.screenWaitMs +
                "ms; instantiating once without a screen host");
            smokeRoot.screenHosts.push({ name: "<no-screen>", host: smokeRoot });
        }
        for (const entry of smokeRoot.screenHosts) {
            console.info("SMOKE NOTE instantiating widget set for screen " + entry.name);
            smokeRoot.instantiateSet(entry.name, entry.host);
        }
    }

    function instantiateSet(screen: string, host: Item): void {
        // Every screen gets its own full set: a widget that only breaks on the
        // second monitor (the class of bug the spec calls out) must fail here.
        for (const w of smokeRoot.contractWidgetPlan) {
            // A widget that opens a panel needs a coordinator to open it on, and
            // it needs its OWN: a shared one is the multi-monitor bug this
            // harness exists to catch. So the per-screen state is built here and
            // handed in, and a widget that does not declare a panel simply
            // ignores it (BarWidget's `panelCoordinator` defaults to null).
            const extra = w.perScreenCoordinator === true
                ? { panelCoordinator: smokeRoot.makeCoordinator(screen, host) }
                : {}
            smokeRoot.instantiateOne("widget", w.name, w.path, w.props, host, screen,
                w.singleton === true, w.probe, false, extra);
        }
        for (const c of smokeRoot.configPlan) {
            smokeRoot.instantiateOne("config", c.name, c.path, c.props, host, screen,
                c.singleton === true, c.probe, c.loadOnly === true);
        }
        // The panel architecture, per screen for the same reason: two screens'
        // coordinators sharing one slot is exactly the bug this harness catches.
        for (const p of smokeRoot.panelPlan) {
            const extra = p.perScreenCoordinator === true
                ? { panelCoordinator: smokeRoot.makeCoordinator(screen, host) }
                : {}
            smokeRoot.instantiateOne("panel", p.name, p.path, p.props, host, screen,
                false, p.probe, p.loadOnly === true, extra)
        }
        for (const c of smokeRoot.componentPlan) {
            smokeRoot.instantiateOne("component", c.name, c.path, c.props, host, screen);
        }
    }

    // One PanelCoordinator per screen, built from the SHIPPED file. A stub here
    // could agree with itself about behaviour the real one does not have, and
    // agreeing with itself is the whole failure mode ticket 10 removed.
    function makeCoordinator(screen: string, host: Item): var {
        const comp = Qt.createComponent("shell/panels/PanelCoordinator.qml")
        if (comp.status !== Component.Ready) {
            console.warn("SMOKE FAIL panel-coordinator(" + screen + ") — failed to load: "
                + comp.errorString())
            return null
        }
        return comp.createObject(host !== null ? host : smokeRoot, {})
    }

    // One PopupState per screen, parented into that screen's host so it dies
    // with the host. Created from the SHIPPED file, not as a stand-in: a stub
    // here could agree with itself about an arity the real widgets do not, and
    // agreeing with itself is the whole failure mode this ticket removed.
    //
    // A failure is WARNED about rather than `mark`ed: `mark` would add a result
    // for a name that is in no plan, and the summary is `planned - passed`, so
    // inventing a result would turn one failure into a phantom second one.
    // Returning null is enough — the widget it was meant for has a REQUIRED,
    // TYPED property, so it fails to construct and that failure IS planned.
    function makePopupState(screen: string, host: Item): var {
        const comp = Qt.createComponent("components/PopupState.qml")
        if (comp.status !== Component.Ready) {
            console.warn("SMOKE FAIL popup-state(" + screen + ") — PopupState failed to "
                + "load: " + comp.errorString());
            return null
        }
        const state = comp.createObject(host !== null ? host : smokeRoot, {})
        if (state === null) {
            console.warn("SMOKE FAIL popup-state(" + screen + ") — PopupState would not "
                + "construct");
        }
        return state
    }

    // `singleton` and `probe` are deliberately untyped: a typed `string`
    // parameter coerces an omitted argument to the literal text "undefined",
    // and then the code calls a function by that name — which fails silently
    // and for the wrong reason. `loadOnly` and `extra` likewise.
    function instantiateOne(kind: string, name: string, path: string, props: var, host: Item, screen: string, singleton, probe, loadOnly, extra): void {
        // A `pragma Singleton` type is constructed by REFERENCING it, not by
        // createObject — createObject on one returns null and would report a
        // false failure. Referencing the imported namespace is both the correct
        // construction and the proof that the registry loads.
        if (singleton === true) {
            try {
                if (probe !== undefined && probe !== null && probe !== "") {
                    smokeRoot[probe]();
                }
                smokeRoot.mark(kind, name, true, "singleton constructed by reference");
            } catch (e) {
                smokeRoot.mark(kind, name, false, "probe threw " + e);
            }
            return;
        }
        const comp = Qt.createComponent(path);
        if (comp.status === Component.Error) {
            smokeRoot.mark(kind, name, false, "component failed to load: " + comp.errorString());
            return;
        }
        if (comp.status !== Component.Ready) {
            smokeRoot.mark(kind, name, false, "component not ready (status " + comp.status + ")");
            return;
        }
        // Compiled and every type it names resolved, but deliberately not
        // created: this entrypoint draws no layer-shell surfaces.
        if (loadOnly === true) {
            smokeRoot.mark(kind, name, true,
                "loaded and type-checked, not instantiated — it owns surfaces and this "
                + "entrypoint draws none");
            return;
        }
        const supplied = props || {}
        const obj = comp.createObject(host !== null ? host : smokeRoot,
            extra === undefined ? supplied : Object.assign({}, supplied, extra))
        if (obj === null) {
            smokeRoot.mark(kind, name, false,
                "createObject returned null — required property missing or object rejected");
            return;
        }
        smokeRoot.mark(kind, name, true, "instantiated on screen " + screen);
    }

    function finalizeStage(): void {
        // Palette readout (ticket 04): printed late, after the file-backed
        // palette has loaded and merged, so the verdict reflects the real
        // theme state rather than the pre-load defaults.
        const pal = UI.Colors;
        console.info("SMOKE NOTE palette source=" + pal.source +
            " keys-from-file=" + pal.keysFromFile +
            (pal.note !== "" ? " note=" + pal.note : "") +
            " background=" + pal.background + " accent=" + pal.accent);

        // The contract's promises (ticket 06), read off real instances. Printed
        // in the same place as the palette verdict — after everything has
        // settled, so a value reported here is the settled value.
        smokeRoot.probeClockPanel();
        smokeRoot.probeTicket15Widgets();
        smokeRoot.probeBaseHover();
        smokeRoot.probeTicket13Widgets();
        smokeRoot.probePlayerWidget();
        smokeRoot.probeMediaServiceRename();
        smokeRoot.probeNotificationWidget();

        // Idle-lock (ticket 17): wait for the helper's status before the summary,
        // because Process output arrives after createObject returns.
        smokeRoot.probeIdleLockWidget(function () {
            smokeRoot.finishSmokeSummary();
        });
    }

    function finishSmokeSummary(): void {
        // The bar's contents (ticket 07): the reader's verdict has already been
        // logged by the singleton itself, so what is added here is that live
        // zone instances were really built from it, and that a widget which
        // cannot be built is skipped rather than fatal.
        smokeRoot.probeZones();
        smokeRoot.probeConstructFailure();
        smokeRoot.probeConfigReader();

        // Per-widget options (ticket 09): what each widget declared, what it
        // was given, and what it rendered — read off widgets built by a real
        // zone from the reader's own verdict.
        smokeRoot.probeWidgetOptions();

        // The bar's layout (ticket 08): the zones' real geometry, measured.
        smokeRoot.probeBarSurface();

        // The panel architecture (ticket 11): the coordinator's state promises
        // and the card's real keyboard focus, both read off live instances.
        smokeRoot.probePanelCoordinator();
        smokeRoot.probePanelCard();
        smokeRoot.probeVolumeWidget();
        smokeRoot.probeNetworkWidget();
        smokeRoot.probeVolumeNetworkPanelSwitch();

        // Services: create each singleton (via the qmldir registration) and
        // read the leaves the shell consumes.
        for (const s of smokeRoot.servicePlan) {
            if (s.name === "NotificationData") {
                smokeRoot.instantiateNotificationData();
                continue;
            }
            smokeRoot.readService(s);
        }

        const planned = smokeRoot.planned.length;
        const passed = smokeRoot.results.filter(r => r.ok).length;
        const failed = planned - passed;
        console.info("SMOKE SUMMARY planned=" + planned + " passed=" + passed + " failed=" + failed +
            (failed === 0 ? " — all items instantiated" : ""));
        Qt.quit(); // the verifier kills the process anyway; quit is a courtesy
    }

    function readService(s: var): void {
        try {
            smokeRoot.mark("service", s.name, true, s.read());
        } catch (e) {
            smokeRoot.mark("service", s.name, false, "readout threw " + e);
        }
    }

    // NotificationData is a plain type in services/qmldir (not a singleton), so
    // it is instantiated like a component instead of read through a singleton.
    function instantiateNotificationData(): void {
        const comp = Qt.createComponent("services/NotificationData.qml");
        if (comp.status !== Component.Ready) {
            smokeRoot.mark("service", "NotificationData", false,
                "component failed to load: " + comp.errorString());
            return;
        }
        const obj = comp.createObject(smokeRoot, {});
        if (obj === null) {
            smokeRoot.mark("service", "NotificationData", false, "createObject returned null");
            return;
        }
        // Prove the object is live, not merely constructed: its own property
        // is readable and writable, and its auto-dismiss timer is armed.
        obj.seqId = "smoke";
        smokeRoot._notifDataSeqId = obj.seqId;
        if (obj.seqId !== "smoke") {
            smokeRoot.mark("service", "NotificationData", false, "round-trip of seqId failed");
            return;
        }
        smokeRoot.mark("service", "NotificationData", true,
            "instance created and mutated (expireTimeout " + obj.expireTimeout + "ms)");
    }
}
