import QtQuick
import QtQuick.Controls

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

        onClicked: widget.activate(widget)

        // A widget with no tooltip sets tooltip to "", and nothing is shown —
        // the empty case is a value, not a missing member.
        ToolTip.visible: widget.hovered && widget.tooltip !== ""
        ToolTip.delay: 400
        ToolTip.text: widget.tooltip
    }
}