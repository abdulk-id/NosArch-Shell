import QtQuick
import QtQuick.Controls

import "../panels" as Panels

// BarWidget — THE widget contract (ticket 06).
//
// Every bar widget extends this (directly, or through SimpleBarWidget) and
// therefore declares the same interface. The contract is:
//
//   REQUIRED — the widget cannot be constructed without them:
//     content        Component   what the bar shows
//     activate       var         the click action, called as activate(widget)
//     tooltip        string      hover text
//
//   OPTIONAL — genuinely optional, and the distinction is load-bearing:
//     panelContent   Component   defaults to null. A widget that offers a panel
//                                supplies it; a widget that does not, does NOT
//                                supply an empty one. `hasPanel` is how the
//                                rest of the shell tells those apart, so a
//                                widget never has to pretend.
//     panelCoordinator PanelCoordinator
//                                defaults to null, and is on the CONTRACT for
//                                the same reason `panelContent` is: the widget
//                                needs a way to ASK for its panel, and a widget
//                                that has no panel must not have to invent a
//                                no-op to satisfy the type. BarZone assigns the
//                                surface's coordinator to a widget that declares
//                                a panel, and to no other — see BarZone.qml.
//     options        var         defaults to {} — the settings carried by this
//                                widget's configuration entry, handed over at
//                                construction. Assigned by BarZone, read with
//                                optionValue(); see the block below.
//
// WHY `required`, AND NOT A CONVENTION
//
//   Qt enforces `required` at instantiation: an object missing one is not
//   constructed (verified on the installed Quickshell 0.3.2 — see
//   scripts/verify-widget-contract.sh). So a widget that forgets a member is a
//   load error caught by the smoke test, not a silent absence discovered when a
//   user clicks. A derived class MAY satisfy a base's required property by
//   assigning it in its own body — which is exactly what SimpleBarWidget does,
//   and what keeps trivial widgets from declaring capabilities they lack.
//
// WHY THE HOVER AFFORDANCE IS HERE AND NOT IN EACH WIDGET
//
//   Dimming when not hovered and brightening on hover is how a user tells
//   which bar widgets are interactive (spec story 52). It is uniform by
//   definition, so it belongs to the contract: a widget cannot get it subtly
//   wrong, and no widget re-implements a MouseArea to get it.
Item {
    id: widget

    // ---- the contract: required -------------------------------------------
    required property Component content
    required property var activate
    required property string tooltip

    // ---- the contract: optional panel content ------------------------------
    // null, not an empty Component. A widget with no panel leaves this alone.
    property Component panelContent: null
    readonly property bool hasPanel: widget.panelContent !== null

    // How this widget ASKS for its panel (ticket 11).
    //
    // A widget does not open a panel itself: it holds the coordinator for its
    // own surface and calls `toggle(panelId, widget)` on it. That one call is
    // both directions — open, and close-if-already-open — because a widget that
    // opened its panel and was then told it was somehow not open is the failure
    // the two-call version invites.
    //
    // It is here, on the contract, rather than in each panel-bearing widget for
    // the same reason the hover affordance is: the rule for "how do I ask" has
    // to be the same for every widget, or twelve widgets will answer it twelve
    // ways. A widget with no panel never calls it and never sees a coordinator.
    property Panels.PanelCoordinator panelCoordinator: null

    // The convenience the contract owns, so no widget has to write the same
    // null-check twice: open my panel if it is shut, close it if it is open.
    // Returns whether a panel is now open on this surface, which is what the
    // caller usually wants to know anyway.
    function togglePanel(panelId: string): bool {
        if (widget.panelCoordinator === null || widget.panelId === "") {
            return false
        }
        widget.panelCoordinator.toggle(widget.panelId, widget)
        return widget.panelCoordinator.hasOpenPanel
    }

    // The id this widget's panel is known by on its surface's coordinator.
    //
    // It lives on the contract, beside `togglePanel`, because the two are one
    // mechanism: a widget that declares `panelContent` also declares the name it
    // is opened under, and a widget that declares neither declares neither. A
    // panel with no id could not be opened, so there is no default that would be
    // better than "" — an empty id means "this widget has no panel", which is
    // what a widget with no `panelContent` already says for itself.
    //
    // The id is per-surface state, not a global registry: two monitors can have
    // their own volume panel open at the same time, and neither knows the
    // other's exists.
    // A widget's own name, used to build its default panel id.
    //
    // NOT `readonly`, and that is load-bearing rather than untidy. A derived QML
    // type cannot re-declare a base `readonly` property — the derived value is
    // silently ignored, so the widget appears to have named itself and every id
    // in the shell comes out empty (verified: a `readonly` `widgetName` on a
    // derived widget left `panelId` as "panel-"). It is declared plain so a
    // widget may ASSIGN it, which is the only override form QML allows. Read-only
    // reporting then lives on `panelId`, a different name. The same trap and the
    // same fix as `optionDefaults`; see the note there.
    property string widgetName: ""

    // The id this widget's panel is known by on its surface's coordinator.
    //
    // The id is per-surface state, not a global registry: two monitors can each
    // have their own volume panel open at once, and neither knows the other
    // exists. An empty id means "this widget has no panel", which is what a
    // widget with no `panelContent` already says for itself — so there is no
    // default here that would be better than "".
    readonly property string panelId: widget.hasPanel
        ? "panel-" + widget.widgetName
        : ""

    // ---- the contract: per-widget options (ticket 09) -----------------------
    //
    // A widget says which options it takes by ASSIGNING optionDefaults, and
    // reads them back with optionValue(). Both live here, on the contract,
    // rather than in each widget, for the same reason the hover affordance
    // does: the rule for "what happens to a key I did not ask for" has to be
    // the same everywhere, or twelve widgets will answer it twelve ways.
    //
    // WHY optionDefaults IS NOT `readonly` — a QML constraint, not an oversight
    //
    //   A derived type cannot override a base class's `readonly` property.
    //   Assigning to one fails to COMPILE: "Invalid property assignment:
    //   \"optionDefaults\" is a read-only property" (verified on the installed
    //   Quickshell 0.3.2 — see quickshell-api-notes.md). So a readonly
    //   declaration here would make every widget's own option list
    //   unreachable while still compiling clean, which is the worst kind of
    //   failure: it looks like it works and quietly takes no effect.
    //   Declaration by ASSIGNMENT is the only form QML lets a derived type
    //   override, which is why `hasPanel`-style read-only reporting is spelled
    //   `readonly property` on a DIFFERENT name.
    //
    // WHY ONE `options` OBJECT AND NOT ONE PROPERTY PER OPTION
    //
    //   Configuration entries are objects with arbitrary extra keys, and
    //   BarZone builds the widget through Component.createObject(). Assigning
    //   an unknown named property there is silently ignored by createObject but
    //   THROWS on a live object ("Cannot assign to non-existent property"), so
    //   per-option properties would make the delivery of every option the
    //   shell does not know about a runtime error — exactly the thing ADR 0003
    //   forbids, arriving from a perfectly ordinary configuration file.
    //   One `var` options bag has neither failure mode, and it means adding an
    //   option to a widget is a change to ONE widget file.
    property var options: ({})

    // The options THIS widget takes, as name → default. Empty here, and
    // deliberately so: a widget with nothing to tune declares nothing, exactly
    // as one with no panel declares no panelContent. An entry that names no
    // option is therefore a valid, silent, no-op configuration — not an error.
    property var optionDefaults: ({})

    // Whether this widget takes any option at all. Read rather than inferred
    // from optionDefaults' contents at the call site, so "a widget with no
    // options" is a value and not a special case everywhere it is examined.
    readonly property bool hasOptions: Object.keys(widget.optionDefaults).length > 0

    // The keys this widget was GIVEN that it does not DECLARE.
    //
    //   This is the list the rest of the shell reports, and it exists so that
    //   "ignored" and "not applicable" are distinguishable. Without it, a
    //   misspelt option and a correctly-spelled one are indistinguishable in
    //   the log, and a user who wrote one has no way to learn it did nothing —
    //   which is the same failure the `path`/`file` rule exists to prevent, in
    //   a more expensive costume.
    readonly property var unrecognisedOptions: {
        const out = []
        if (widget.options === undefined || widget.options === null) {
            return out
        }
        const declared = Object.keys(widget.optionDefaults)
        const given = Object.keys(widget.options)
        for (let i = 0; i < given.length; i++) {
            if (declared.indexOf(given[i]) === -1) {
                out.push(given[i])
            }
        }
        return out
    }

    // One option's value: the configuration's if it set one, otherwise the
    // widget's own declared default.
    //
    //   Every widget reads its options through this and nothing else, so
    //   "absent means the default" is decided once. A widget reaching into
    //   `options` directly would have to repeat that rule — and would get it
    //   subtly differently, which is how a widget ends up rendering
    //   "undefined" to a user who simply did not set an option.
    //
    //   Deliberately un-annotated on the return (`var`, not the default's
    //   type): one function reads options of every type, and annotating it
    //   would coerce a string option to a bool default or vice versa. Unknown
    //   NAME rather than a schema — nothing here validates, because nothing
    //   here can know what a given widget considers usable.
    function optionValue(name: string): var {
        if (widget.options !== undefined && widget.options !== null
                && widget.options[name] !== undefined) {
            return widget.options[name]
        }
        return widget.optionDefaults === undefined ? undefined : widget.optionDefaults[name]
    }

    // ---- clicks the content handles itself ---------------------------------
    //
    // Workspaces and the tray place their own MouseAreas inside `content` (one
    // per workspace, one per icon with three buttons). The contract's overlay
    // MouseArea sits above the Loader and would swallow those clicks if it
    // accepted them. Widgets that handle clicks internally set this true; the
    // overlay then tracks hover and tooltip only.
    property bool contentHandlesClicks: false

    // ---- the hover affordance (contract-owned, never re-implemented) -------
    property real dimOpacity: 0.55
    property real brightOpacity: 1.0
    readonly property bool hovered: mouse.containsMouse
    readonly property real contentOpacity: widget.hovered ? widget.brightOpacity : widget.dimOpacity

    implicitWidth: contentLoader.item ? contentLoader.item.implicitWidth : 0
    implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

    Loader {
        id: contentLoader

        anchors.fill: parent
        // The dimming is applied to the CONTENT, so a widget's own panel and
        // any decoration outside the content are unaffected by bar hover state.
        opacity: widget.contentOpacity
        sourceComponent: widget.content
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: widget.contentHandlesClicks ? Qt.NoButton : Qt.AllButtons

        onClicked: widget.activate(widget)

        // A widget with no tooltip sets tooltip to "", and nothing is shown —
        // the empty case is a value, not a missing member.
        ToolTip.visible: widget.hovered && widget.tooltip !== ""
        ToolTip.delay: 400
        ToolTip.text: widget.tooltip
    }
}