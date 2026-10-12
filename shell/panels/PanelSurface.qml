import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQml

import "../ui" as UI
import "."

// PanelSurface — the full-screen overlay a panel is drawn on (ticket 11).
//
// ---------------------------------------------------------------------------
// WHY A LAYER-SHELL SURFACE AND NOT A FRAMEWORK POPUP
// ---------------------------------------------------------------------------
//
//   An interactive PopupWindow does not take keyboard focus until it is clicked
//   or hovered. A panel summoned by a keybind would open and then swallow every
//   keypress, which makes a panel you are meant to type into impossible. So a
//   panel is a full-screen PanelWindow on the Overlay layer with the card
//   positioned inside it, and this file is the whole of that decision's
//   implementation. See docs/adr/0002 for why the popup path was abandoned
//   rather than debugged, and for what was deleted with it.
//
//   The framework popup is gone from the panel architecture entirely: no
//   PopupWindow, no grabFocus, and no recursive walk clearing `focus` on every
//   descendant. That walk existed only to stop focus grabbing from dismissing
//   the panel when the volume slider inside it was dragged — and it achieved
//   that by disabling focus everywhere, which is the opposite of what a panel
//   is for. Dragging the slider now has nothing to fight: nothing in this
//   architecture watches the pointer to decide whether to dismiss.
//
// ---------------------------------------------------------------------------
// THE FOUR THINGS THIS FILE OWES THE TICKET, AND WHY EACH IS HERE
// ---------------------------------------------------------------------------
//
//   1. THE FOCUS PRIME.  On open the surface asks for EXCLUSIVE keyboard focus,
//      and a short timer drops it to ON-DEMAND. Exclusive alone would make the
//      compositor route every pointer event on every output here, which breaks
//      clicks on other monitors — the prime is what buys keyboard input at
//      open time without that side effect. `keyboardFocus` is a plain bindable
//      property on the layer shell: the surface is reconfigured in place, not
//      destroyed and recreated (the layer-surface id is identical either side of
//      the switch — measured on this machine, see scripts/verify-panels.sh).
//
//   2. THE IN-SURFACE FOCUS TARGET.  Layer-shell focus alone gives the SURFACE
//      keyboard focus, not an in-surface item active focus, so a key handler
//      inside the panel would never fire. Once this surface has mapped, the
//      card is told to force focus onto a real item inside itself. After a
//      timer, because before the compositor has the surface there is nothing
//      to focus and the attempt would fail silently and stay failed.
//
//   3. THE DISMISSAL MASK.  This surface covers the whole screen, so without a
//      mask the bar underneath would be unclickable while a panel is open. The
//      mask is a Region (Quickshell CORE, not Quickshell.Wayland) set to the
//      Xor of the bar strip: the screen MINUS the strip. Region masks input,
//      not paint — the bar is still drawn by its own surface, just left alone
//      by this one. That is what lets a panel stay open while the widgets in
//      the bar remain clickable, which is in turn what makes switching panels
//      in one click possible at all.
//
//   4. THE CROSS-OUTPUT TWIN.  Pointer input is hit-tested per output, so a
//      full-screen surface on one monitor cannot see a click on another. Each
//      OTHER output therefore gets a transparent twin that exists only to be
//      clicked: clicking it dismisses the panel, which is the promise that
//      clicking anywhere always dismisses.
//
// ---------------------------------------------------------------------------
// HYPRLAND, AND ONLY HYPRLAND
// ---------------------------------------------------------------------------
//
//   The focus model above depends on compositor behaviour confirmed under
//   Hyprland and nowhere else — layer-shell exclusive focus especially. Porting
//   to another compositor means a DIFFERENT PANEL BASE, not a different panel:
//   widgets declare `panelContent` and know nothing about any of this. The
//   trade is deliberate and recorded in ADR 0002; it is repeated here because a
//   reader debugging focus on another compositor needs to know this file is
//   where the assumption lives. (On this machine, verified: the compositor's
//   default Auto exclusion mode reserved the BAR's exclusive zone and handed
//   this surface y=85/height=995 instead of 0/1080 — hence ExclusionMode.Ignore
//   below, which is load-bearing, not tidy.)
Scope {
    id: layer

    // The screen this layer serves. Not named `screen`: PanelWindow already has
    // a `screen` property and shadowing it would be a trap for whoever edits
    // this next.
    required property var targetScreen

    // The coordinator that owns this surface's one panel slot. Held, not owned:
    // it lives beside the bar's widgets (BarSurface), which are the things that
    // open panels.
    required property PanelCoordinator coordinator

    // The bar's own geometry, so the card sits under the bar and the mask cuts
    // out exactly the strip the bar occupies.
    property int barHeight: 35

    // ---- the panel's own surface ------------------------------------------
    //
    // Nested inside the bar's PanelWindow on purpose, not beside it: the card is
    // placed from a widget inside the bar's window, and keeping both surfaces
    // in one object scope is what lets the anchor be read without a registry,
    // a screen name, or any other lookup that could be answered wrongly.
    PanelWindow {
        id: surface

        screen: layer.targetScreen

        WlrLayershell.layer: WlrLayer.Overlay
        // A DISTINCT namespace, and the reason the project instructions require
        // one on every overlay surface: this role, the bar's, the twins' and the
        // OSD's must all be tellable apart at runtime. scripts/verify-panels.sh
        // collects every namespace in the tree and fails if one is claimed by
        // two roles.
        WlrLayershell.namespace: "nosarch-shell-panel"

        // The whole screen, not the space left over after the bar's exclusive
        // zone. Measured, not assumed: with the default Auto the compositor
        // handed this surface 0,85,1920x995.
        exclusionMode: ExclusionMode.Ignore

        color: "transparent"

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        // ---- ownership: the LOGICAL state, never `visible` ------------------
        //
        // Visible, masked and focusable all hang off the coordinator's
        // `ownsInput`, which is derived from whether a panel id is set — not
        // from whether this window happens to be drawn. A close animation
        // therefore cannot hold the user's clicks or the keyboard for its own
        // duration: the id is cleared, ownership ends that instant, and the
        // card fades out of a surface that is already letting go.
        readonly property bool ownsInput: layer.coordinator.ownsInput

        visible: surface.ownsInput

        // Two regions, chosen by the LOGICAL state — never by `visible`.
        //
        //   interactiveRegion  Xor of the bar strip, i.e. the screen MINUS the
        //                      strip: this surface's clickable area while a panel
        //                      is open. Bar widgets stay clickable, which is what
        //                      makes switching panels in one click possible.
        //   inertRegion        empty. An empty region is click-through EVERYWHERE,
        //                      so a panel that has logically closed cannot eat a
        //                      click even for one frame of its fade — the reason
        //                      this is not simply `visible ? interactive : null`,
        //                      since a null mask would be the whole window.
        //
        // Declared as two objects rather than built inline in a binding: a Region
        // written inside a ternary does not parse on this build, and a region
        // rebuilt on every re-evaluation of the binding would be re-negotiated
        // with the compositor each time for no reason.
        //
        // Both regions are declared in the LAYER below, not here. A `Region`
        // written into a PanelWindow's `data` default property is not a child of
        // anything the window knows about — the mask binding then reads
        // `undefined` and logs "Unable to assign [undefined] to PendingRegion*",
        // which is how a panel ends up with a null mask (the whole window
        // clickable) while looking perfectly correct. Declared out here, both
        // exist before the window's bindings are first evaluated.
        mask: surface.ownsInput ? interactiveRegion : inertRegion

        // ---- the focus prime -------------------------------------------------
        property bool primed: false

        // How long exclusive focus is held before dropping to on-demand.
        //
        // 140ms by default — long enough for the compositor to grant the surface
        // keyboard focus (which is what makes the panel typeable at open time)
        // and short enough that the user's keyboard is not noticeably taken. The
        // whole point of dropping is that exclusive focus routes every pointer
        // event on EVERY output here, so any time spent in it is time the rest of
        // the desktop cannot be clicked.
        //
        // Overridable by environment so a verifier can shorten it; not a
        // configuration key, because it is a shell constant rather than a user
        // preference (the schema stays minimal).
        readonly property int focusPrimeMs:
            parseInt(Quickshell.env("NOSARCH_PANEL_PRIME_MS") || "") || 140

        readonly property string focusMode: !surface.ownsInput ? "None"
            : (surface.primed ? "OnDemand" : "Exclusive")

        // Three members, and there is no fourth: `WlrKeyboardFocus.Exact` looks
        // plausible, does not exist on this build, and evaluates to undefined
        // with no error at all (quickshell-api-notes.md §6) — the same silent
        // shape of failure as Qt.TimeFormat. Named here so the next editor
        // does not "fix" it to Exact.
        WlrLayershell.keyboardFocus: !surface.ownsInput ? WlrKeyboardFocus.None
            : (surface.primed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)

        Timer {
            id: focusPrim
            running: surface.ownsInput && !surface.primed
            interval: surface.focusPrimeMs
            onTriggered: surface.primed = true
        }

        // ---- the dismissal surface -------------------------------------------
        //
        // The BOTTOM child, with the card above it. That ordering is the whole
        // of "a dismissing overlay never swallows my clicks on the controls
        // inside it": the card's own controls are later siblings, so they are
        // on top and receive the click, and the dismissal area only ever sees
        // clicks that landed outside the card.
        MouseArea {
            anchors.fill: parent
            onClicked: layer.coordinator.close()
        }

        // ---- the card -------------------------------------------------------
        PanelCard {
            id: card

            panelId: layer.coordinator.openId
            panelCoordinator: layer.coordinator
            content: layer.panelContent

            width: layer.cardWidth
            height: implicitHeight

            // Top-bar-only placement, and the clamp that keeps it on screen.
            x: layer.placedX
            y: layer.barBottom + layer.cardGap

            // Opacity is the ONLY thing the animation touches. It is never
            // `visible`: a card that faded out over a still-present window
            // would keep that window's mask, and with it the user's clicks.
            opacity: layer.coordinator.hasOpenPanel ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: layer.animationMs
                    easing.type: Easing.OutCubic
                }
            }
        }

        // ---- reporting -------------------------------------------------------
        //
        // Read by scripts/verify-panels.sh. The surface reports what it is and
        // where it put the card; it does not claim the placement is right. The
        // containment check is made by the verifier against the framework's own
        // screen list, from two independently produced numbers.
        function describe(): string {
            return "surface=" + layer.screenName
                + " namespace=" + (surface.WlrLayershell === null ? "none" : surface.WlrLayershell.namespace)
                + " focus=" + surface.focusMode
                + " mapped=" + Math.round(surface.width) + "x" + Math.round(surface.height)
                + " mask=" + (surface.mask === null ? "none" : "region")
                + " owner=" + (surface.ownsInput ? "yes" : "no")
                + " twins=" + layer.twins.length
        }

        function describePlacement(): string {
            return "surface=" + layer.screenName
                + " panel=" + (layer.coordinator.openId === "" ? "none" : layer.coordinator.openId)
                + " anchor=" + (layer.anchorX === 0 && layer.anchorY === 0
                    ? "none" : Math.round(layer.anchorX) + "," + Math.round(layer.anchorY))
                + " card=" + Math.round(card.x) + "," + Math.round(card.y)
                    + "," + Math.round(card.width) + "," + Math.round(card.height)
                + " screen=" + layer.screenWidth + "x" + layer.screenHeight
                + " topBarOnly=yes"
        }

    }

    // ---- placement ----------------------------------------------------------
    //
    // Top-bar only, recorded as SCOPE rather than left as an accident: the bar
    // is drawn at the top edge and nothing else is implemented, so a card is
    // placed below the bar's strip. Left, right and bottom bars are not
    // implemented and adding one is a contained change (docs/known-gaps.md).
    property int cardGap: 6
    property int cardWidth: 320
    property int edgeMargin: 4
    property int animationMs: 140

    readonly property int screenWidth: layer.targetScreen === null
        || layer.targetScreen === undefined ? 0 : layer.targetScreen.width
    readonly property int screenHeight: layer.targetScreen === null
        || layer.targetScreen === undefined ? 0 : layer.targetScreen.height
    readonly property string screenName: layer.targetScreen === null
        || layer.targetScreen === undefined ? "<no-screen>" : layer.targetScreen.name

    // Where the bar's strip ends, in this surface's own coordinates: the
    // floating inset the bar window is drawn at, plus its height. Read from the
    // configuration beside the bar's own geometry rather than re-guessed here.
    property int barInset: 8
    readonly property int barBottom: layer.barHeight + layer.barInset

    // The anchor: the widget that opened the panel, mapped into THIS window's
    // coordinates. The card is centred under it and then clamped, so the promise
    // is "under the widget that opened it, inside the screen" and neither half
    // can fail alone.
    //
    // WHY THE MAPPING IS A HAND-OFF RATHER THAN A BINDING
    //
    //   `surface.mapFromItem(widget, 0, 0)` is a function call, and QML tracks
    //   dependencies through property READS inside a binding — not through what a
    //   called function happens to touch. Written as a binding it therefore
    //   evaluated once, read whatever the geometry was at that instant (0,0,
    //   because the bar had not been laid out), and never re-evaluated: the card
    //   stayed at the left margin for the rest of the panel's life while the
    //   reported anchor was correct. Observed on this machine before this comment
    //   existed — anchor=1882,0 with the card still at x=4.
    //
    //   So the point is computed imperatively and stored in a PLAIN property,
    //   which is writable, and the inputs that can move it are enumerated: the
    //   anchor changing, its geometry changing, and the surface being resized.
    //   Everything that can move the card is in `anchorKey`, so nothing can move
    //   the card without also recomputing it.
    property Item anchorWidget: layer.coordinator.anchorWidget
    property real anchorX: 0
    property real anchorY: 0

    function measureAnchor(): void {
        const w = layer.anchorWidget
        if (w === null || w === undefined) {
            layer.anchorX = 0
            layer.anchorY = 0
            return
        }
        const p = surface.mapFromItem(w, 0, 0)
        layer.anchorX = p.x
        layer.anchorY = p.y
    }

    readonly property string anchorKey: (layer.anchorWidget === null ? "none"
        : (layer.anchorWidget.width + "x" + layer.anchorWidget.height))
        + "|" + surface.width + "x" + surface.height

    onAnchorKeyChanged: layer.measureAnchor()

    Connections {
        target: layer.anchorWidget
        // x/y/width/height are the anchor's OWN geometry; the panel card only
        // cares about where the widget ended up, and re-measuring on any of
        // these keeps the two in step when the bar is rebuilt under an open panel.
        function onXChanged() { layer.measureAnchor() }
        function onYChanged() { layer.measureAnchor() }
        function onWidthChanged() { layer.measureAnchor() }
        function onHeightChanged() { layer.measureAnchor() }
    }

    readonly property real anchorCentre: layer.anchorX + (layer.anchorWidget === null
        ? 0 : layer.anchorWidget.width / 2)

    readonly property int placedX: {
        // Centre on the anchor, then keep the whole card on screen. Both
        // branches are arithmetic on the card's own width, so a card wider than
        // the screen lands on the left margin rather than off the edge.
        const want = layer.anchorCentre - card.width / 2
        const maxX = Math.max(layer.edgeMargin, layer.screenWidth - card.width - layer.edgeMargin)
        return Math.max(layer.edgeMargin, Math.min(want, maxX))
    }

    // The widget's own panel content, read off the anchor. A widget with no
    // panel declares no panelContent, so this is legitimately null and the card
    // renders empty rather than the shell inventing content.
    readonly property Component panelContent: {
        const w = layer.anchorWidget
        if (w === null || w === undefined) {
            return null
        }
        const c = w.panelContent
        return (c === undefined || c === null) ? null : c
    }

    // ---- focus after the surface maps --------------------------------------
    //
    // The second half of the promise "the panel accepts keyboard input the
    // instant it opens". The prime gets the SURFACE the keyboard; this gets an
    // in-surface ITEM the focus, without which a key handler inside the panel
    // never fires.
    //
    // On a timer, and restarted whenever the open panel changes, because a
    // surface that has just been given a different card has no focus in it yet.
    property bool focusReported: false
    readonly property string focusKey: layer.coordinator.openId + "|" + surface.ownsInput

    onFocusKeyChanged: {
        if (!surface.ownsInput) {
            layer.focusReported = false
            // Re-prime on the next open: the prime exists to get the keyboard
            // AT OPEN TIME, and a panel that reopens must get it again.
            surface.primed = false
            return
        }
        settleFocus.restart()
    }

    Timer {
        id: settleFocus
        interval: 90
        repeat: false
        onTriggered: {
            const arrived = card.focusContent()
            layer.focusReported = true
            console.info("nosarch-shell ▸ PANEL focus surface=" + layer.screenName
                + " arrived=" + (arrived ? "yes" : "NO")
                + " card=" + card.describe())
        }
    }

    // ---- the twins on every OTHER output ------------------------------------
    //
    // Transparent, click-through for anything but a dismissal, and unable to
    // take keyboard focus: a twin that could be focused would take the keyboard
    // away from the panel the user opened, on a different monitor, silently.
    // Its namespace is its own role's, distinct from the panel's.
    //
    // On one monitor this list is empty, which is exactly why the cross-monitor
    // behaviour is recorded as a known gap rather than claimed: it has never
    // run with a second output attached.
    readonly property var otherScreens: {
        const out = []
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name !== layer.screenName) {
                out.push(screens[i])
            }
        }
        return out
    }

    readonly property var twins: twinWindows.instances

    Variants {
        id: twinWindows
        model: layer.otherScreens

        delegate: Component {
            PanelWindow {
                id: twin

                required property var modelData
                screen: modelData

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "nosarch-shell-panel-dismiss"
                // No keyboard focus at all: this surface exists to be clicked.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                focusable: false

                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                // A twin exists exactly while the panel is open, and covers its
                // whole output: a click anywhere on another monitor dismisses,
                // including over that monitor's bar, because the panel it is
                // dismissing belongs to a different screen and those widgets are
                // not the ones in play.
                //
                // No mask at all, which is the point: `mask: Region {}` would be
                // an EMPTY region — click-through everywhere — and a twin that
                // cannot be clicked dismisses nothing. The default (no mask) is
                // the whole window.
                visible: layer.coordinator.ownsInput

                MouseArea {
                    anchors.fill: parent
                    onClicked: layer.coordinator.close()
                }
            }
        }
    }

    // ---- the activation driver (verification only) -------------------------
    //
    // NOSARCH_PANEL_DRIVER=<verb>:<panel-id> makes this surface drive one
    // widget's own `activate(widget)` call, which is exactly what the bar's
    // MouseArea does on a click. scripts/verify-panels.sh uses it to open a real
    // panel in the real shell, because there is no pointer-injection tool on this
    // machine (wtype is keyboard-only, and Hyprland 0.56 has no click dispatcher)
    // — and driving the coordinator from outside would exercise the coordinator
    // while skipping the wiring that reaches it, which is the half most likely to
    // be wrong.
    //
    // It is OFF unless the variable is set, so the live desktop's shell is never
    // affected by it, and it opens the panel by the same call a user makes.
    //
    // What it still does NOT cover: Qt's own hit-testing, which decides whether a
    // click at a given point lands on this widget at all. That remains manual, and
    // is recorded in docs/known-gaps.md.
    readonly property string driverCommand: Quickshell.env("NOSARCH_PANEL_DRIVER") || ""
    property bool driverRan: false

    function runDriver(): void {
        if (layer.driverRan || layer.driverCommand === "") {
            return
        }
        const parts = layer.driverCommand.split(":")
        if (parts[0] !== "open") {
            return
        }
        const wanted = parts.slice(1).join(":")
        const widget = layer.findWidgetDeclaring(wanted)
        if (widget === null) {
            console.warn("nosarch-shell ▸ PANEL driver asked for panel \"" + wanted
                + "\" and no widget on this surface declares it")
            return
        }
        layer.driverRan = true
        // The activation ACTION, not the coordinator. `activate` is the contract's
        // click handler and is what a real click invokes.
        if (widget.activate !== undefined && widget.activate !== null) {
            widget.activate(widget)
        }
    }

    // The built widget declaring this panel id, or null. Read off the bar surface
    // beside the widgets, so the driver uses the same objects the bar does.
    function findWidgetDeclaring(panelId: string): Item {
        const holder = layer.barSurface
        if (holder === null || holder === undefined || holder.panelWidgets === undefined) {
            return null
        }
        const widgets = holder.panelWidgets
        for (let i = 0; i < widgets.length; i++) {
            const declared = widgets[i].panelId
            // Matched against the widget's OWN id and, for convenience, against
            // the bare name it was derived from — so the driver can be asked for
            // `volume` rather than `panel-volume`. Two spellings of one thing is
            // acceptable HERE and nowhere else: this is a test driver, and making
            // it match the real id exactly would mean every future verifier has
            // to know how ids are built.
            if (declared === panelId
                    || (typeof declared === "string"
                        && declared.length > 6
                        && declared.substring(6) === panelId)) {
                return widgets[i]
            }
        }
        return null
    }

    // The bar surface this panel hangs from. Required, and not derivable: the card
    // is placed from a widget in ANOTHER window (the bar's), and reading its
    // geometry needs the item to be alive and placed.
    property Item barSurface: null

    // ---- the bar strip, which the mask cuts out -----------------------------
    //
    // Geometry only, and a Rectangle rather than an Item so it is a real
    // rectangle for the region without needing a paint.
    //
    // It lives in the LAYER, not inside the panel window, because the region that
    // uses it is declared here and a Region can only reference an item in scope.
    // Transparent rather than `visible: false` on purpose: a mask built from an
    // item that is hidden must still be built from its geometry, and making
    // visibility the deciding factor risks the cut-out silently disappearing —
    // which would leave the bar unclickable while everything still looked right.
    Rectangle {
        id: barStrip

        color: "transparent"
        x: 0
        y: 0
        width: surface.width
        height: layer.barHeight + layer.barInset
    }

    // ---- the two regions ----------------------------------------------------
    //
    // Interactive: Xor of the bar strip, i.e. the screen MINUS the strip. This is
    // what keeps the bar widgets clickable while a panel is open, and therefore
    // what makes switching panels in one click possible.
    //
    // Inert: empty, which is click-through EVERYWHERE. A closed panel uses this
    // rather than `null`, because a null mask means the WHOLE window — a panel
    // that has logically closed but is still fading would keep swallowing clicks
    // for the length of the animation.
    Region {
        id: interactiveRegion
        item: barStrip
        intersection: Intersection.Xor
    }

    Region {
        id: inertRegion
    }

    // ---- reporting ----------------------------------------------------------
    //
    // One line per distinct state. The shell tells the verifier what it built;
    // the verifier decides what is true of it. A component that reported its
    // own success would make the run vacuous.
    property string _lastState: ""
    property string _lastPlace: ""

    readonly property string stateKey: layer.coordinator.describe()
        + "|" + surface.focusMode + "|" + surface.ownsInput + "|" + card.describe()

    readonly property string placeKey: layer.placedX + "|" + card.y + "|"
        + card.width + "|" + card.height + "|" + layer.coordinator.openId
        + "|" + layer.anchorX + "|" + layer.anchorY

    onStateKeyChanged: layer.reportState()
    onPlaceKeyChanged: layer.reportPlacement()

    // The driver runs once the bar has settled: before that the widgets have no
    // geometry, so a panel opened at t=0 would be placed against a bar that does
    // not exist yet.
    readonly property string driverKey: layer.driverRan ? "done"
        : (layer.barSurface === null ? "" : (layer.barSurface.settledKey || ""))

    onDriverKeyChanged: {
        if (layer.driverKey !== "done" && layer.driverKey !== "") {
            driverTimer.restart()
        }
    }

    Timer {
        id: driverTimer
        interval: 120
        repeat: false
        onTriggered: layer.runDriver()
    }

    function reportState(): void {
        const line = "nosarch-shell ▸ PANEL state " + surface.describe()
            + " " + card.describe()
        if (line === layer._lastState) {
            return
        }
        layer._lastState = line
        console.info(line)
    }

    function reportPlacement(): string {
        const line = "nosarch-shell ▸ PANEL place " + surface.describePlacement()
        if (line === layer._lastPlace) {
            return ""
        }
        layer._lastPlace = line
        console.info(line)
        return line
    }
}