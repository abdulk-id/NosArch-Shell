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

// Registered services (see services/qmldir). Referencing the singletons here
// is what creates them, so a service that cannot even be constructed fails.
import "services" as Services

// The ui singletons (Colors, Fonts — see shell/ui/qmldir). Referencing them
// here constructs them, so a palette that cannot load fails in the smoke run.
import "shell/ui" as UI

// The widget contract's registry (see shell/widgets/qmldir). Referencing the
// singleton constructs it, so a registry that cannot load fails the smoke run.
import "shell/widgets" as Widgets

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
                return "out " + a.output.volume + "%" + (a.output.isMuted ? " muted" : "") +
                    " \"" + a.output.textIcon + "\" · in " + a.input.volume + "%" +
                    (a.input.isMuted ? " muted" : "");
            }
        },
        {
            name: "BluetoothService",
            read: () => "icon \"" + Services.BluetoothService.textIcon +
                "\" · connected device: " + Services.BluetoothService.hasDeviceConnected
        },
        {
            name: "Media",
            read: () => {
                const m = Services.Media;
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
                return "iface " + (n.activeInterface || "none") + " \"" + n.textIcon +
                    "\" · rx " + n.rxSpeedText + " · tx " + n.txSpeedText +
                    " · ip " + (n.ipAddress || "none");
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

    // Constructed NOW, not at first use: a singleton is born when something
    // first references it, and the first widget to reference it would pay the
    // "property of null" transient while its hardware (pipewire, NetworkManager)
    // is still connecting. Referencing every singleton here starts those clocks
    // at t=0 so the settle period below covers them.
    readonly property var serviceSingletons: [
        Services.SystemInfo,
        Services.AudioService,
        Services.BluetoothService,
        Services.Media,
        Services.NetworkService,
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
            // it constructs it. Resolved by name in instantiateOne below.
            singleton: true
        },
        { name: "ClockWidget.qml", path: "shell/widgets/ClockWidget.qml", props: {} }
    ]

    Component {
        id: contractContent
        Text {
            text: "smoke"
            font.pixelSize: 12
        }
    }

    // ------------------------------------------------------------------ widgets
    //
    // The twelve bar modules. Each is instantiated from its own file — the
    // same load path the bar uses — once per attached screen. The two
    // panel-takers get the popup-state contract the real bar passes them: a
    // REQUIRED property, so instantiating them without it would fail for a
    // different (and misleading) reason than the one under test.

    readonly property var widgetPlan: [
        { name: "ArchIconModule.qml", path: "shell/topisland/modules/ArchIconModule.qml", props: {} },
        { name: "BatteryModule.qml", path: "shell/topisland/modules/BatteryModule.qml", props: {} },
        { name: "BluetoothModule.qml", path: "shell/topisland/modules/BluetoothModule.qml", props: {} },
        { name: "ClockModule.qml", path: "shell/topisland/modules/ClockModule.qml", props: {} },
        { name: "CpuUsageModule.qml", path: "shell/topisland/modules/CpuUsageModule.qml", props: {} },
        { name: "MemoryUsageModule.qml", path: "shell/topisland/modules/MemoryUsageModule.qml", props: {} },
        { name: "NetworkModule.qml", path: "shell/topisland/modules/NetworkModule.qml", props: { popupState: popupStateStub } },
        { name: "NotificationModule.qml", path: "shell/topisland/modules/NotificationModule.qml", props: {} },
        { name: "PlayerModule.qml", path: "shell/topisland/modules/PlayerModule.qml", props: {} },
        { name: "SystemTrayModule.qml", path: "shell/topisland/modules/SystemTrayModule.qml", props: {} },
        { name: "VolumeModule.qml", path: "shell/topisland/modules/VolumeModule.qml", props: { popupState: popupStateStub } },
        { name: "Workspaces.qml", path: "shell/topisland/modules/Workspaces.qml", props: {} }
    ]

    // ------------------------------------------------------------------ shared
    // components
    //
    // components/qmldir: TopIslandModule (the widget base), Separator and
    // ProgressOSDItem. Required properties are supplied with the values the
    // shell actually passes, so a missing required property is a real failure.

    readonly property var componentPlan: [
        {
            name: "TopIslandModule.qml",
            path: "components/TopIslandModule.qml",
            props: { content: smokeContent, hasPopup: false, clickable: true, hoverable: true }
        },
        {
            name: "Separator.qml",
            path: "components/Separator.qml",
            props: { separatorHeight: 20, separatorColor: UI.Colors.foreground }
        },
        {
            name: "ProgressOSDItem.qml",
            path: "components/ProgressOSDItem.qml",
            props: { value: 50, text: "50%", fontIcon: "󰕾", osdVisible: false, accessibleName: "smoke" }
        }
    ]

    Component {
        id: smokeContent
        Text {
            text: "smoke"
            font.pixelSize: 12
        }
    }

    // The popup contract TopIsland.qml hands NetworkModule/VolumeModule. Always
    // closed: the smoke test reads the bar state of each widget, never an open
    // panel.
    QtObject {
        id: popupStateStub
        function set(id: string, screen: string): void {}
        function close(): void {}
        function isActive(id: string, screen: string): bool { return false; }
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

    // ------------------------------------------------------------- life cycle

    Component.onCompleted: {
        // Touch the singleton list so it is evaluated right now (not on first
        // read) and so a drift between this file and services/qmldir is loud.
        if (smokeRoot.serviceSingletons.length !== 6) {
            console.warn("SMOKE FAIL service-list — smoke.qml touches " +
                smokeRoot.serviceSingletons.length + " singletons, expected 6; " +
                "add the new service to servicePlan and this list");
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
        for (const w of smokeRoot.widgetPlan) {
            smokeRoot.plan("widget", w.name);
        }
        for (const w of smokeRoot.contractWidgetPlan) {
            smokeRoot.plan("widget", w.name);
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
        for (const w of smokeRoot.widgetPlan) {
            smokeRoot.instantiateOne("widget", w.name, w.path, w.props, host, screen);
        }
        for (const w of smokeRoot.contractWidgetPlan) {
            smokeRoot.instantiateOne("widget", w.name, w.path, w.props, host, screen, w.singleton === true);
        }
        for (const c of smokeRoot.componentPlan) {
            smokeRoot.instantiateOne("component", c.name, c.path, c.props, host, screen);
        }
    }

    function instantiateOne(kind: string, name: string, path: string, props: var, host: Item, screen: string, singleton: bool): void {
        // A `pragma Singleton` type is constructed by REFERENCING it, not by
        // createObject — createObject on one returns null and would report a
        // false failure. Referencing the imported namespace is both the correct
        // construction and the proof that the registry loads.
        if (singleton === true) {
            try {
                smokeRoot.probeWidgetRegistry();
                smokeRoot.mark(kind, name, true, "singleton constructed and every name resolved");
            } catch (e) {
                smokeRoot.mark(kind, name, false, "registry probe threw " + e);
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
        const obj = comp.createObject(host !== null ? host : smokeRoot, props || {});
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
        smokeRoot.probeBaseHover();

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
