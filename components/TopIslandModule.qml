import QtQuick
import QtQuick.Layouts
import Quickshell

import "." as Components
import "../shell/ui" as UI

Item {
    id: topIslandModule

    // Content visible in TopIsland
    property Component content: null

    // Mouse behavior
    property bool clickable: true
    property var onClicked: () => {}

    property bool hoverable: false
    property var onHoverEnter: () => {}
    property var onHoverExit: () => {}

    // Popup support
    property bool hasPopup: false
    //
    // The state is TYPED, and that is the point (ticket 10). The pre-rewrite
    // property was an untyped `QtObject` holding a global manager whose
    // `isActive(id, screen)` answered "active on any screen" to a caller that
    // omitted the screen — and the network widget did omit it, so its panel
    // ignored its monitor. There was no way for that to be loud.
    //
    // Here the property can only ever hold a per-surface state object, which
    // takes no screen and therefore cannot be asked a question about one. See
    // components/PopupState.qml for the whole argument; the short version is
    // that "which monitor" is answered by which instance this widget holds,
    // not by a string each widget has to get right.
    property Components.PopupState popupState: null
    property PanelWindow topIsland
    property string popupId: ""

    property Component popupContent: null
    property int popupWidth: 400
    property int popupTopIslandGap: 10
    property int popupMargin: 5
    property int popupSectionMargin: 10

    // Content display in TopIsland
    Loader {
        id: contentLoader

        anchors.fill: parent

        sourceComponent: topIslandModule.content
    }

    implicitWidth: contentLoader.item ? contentLoader.item.implicitWidth : 0
    implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

    // Whether this widget can open a panel at all. One predicate for the
    // click, the visibility and the dismissal, so the three cannot disagree
    // about whether a panel is possible.
    readonly property bool panelPossible: topIslandModule.hasPopup
        && topIslandModule.popupState !== null
        && topIslandModule.popupId !== ""
        && topIslandModule.topIsland !== null

    // Mouse interaction
    MouseArea {
        id: mouseArea

        anchors.fill: parent

        hoverEnabled: topIslandModule.hoverable
        cursorShape: (topIslandModule.clickable || topIslandModule.hoverable) ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: {
            if (topIslandModule.clickable) {
                topIslandModule.onClicked();
            }
            if (!topIslandModule.panelPossible) {
                return;
            }
            // One call, both directions. There is no screen to pass and so no
            // way for two widgets to disagree about which monitor this is.
            const wasOpen = topIslandModule.popupState.isActive(topIslandModule.popupId);
            topIslandModule.popupState.toggle(topIslandModule.popupId);
            if (wasOpen) {
                return;                     // it just closed; nothing to place
            }
            topIslandModule.updatePopupPosition();
            if (popup) {
                popup.anchor.updateAnchor();
            }
        }
        onEntered: {
            if (topIslandModule.hoverable) {
                topIslandModule.onHoverEnter();
            }
        }
        onExited: {
            if (topIslandModule.hoverable) {
                topIslandModule.onHoverExit();
            }
        }

        enabled: topIslandModule.clickable || topIslandModule.hoverable
    }

    // Popup Content
    PopupWindow {
        id: popup
        // The surface's own state decides this, so a panel is visible on the
        // surface whose state says so and on no other.
        visible: topIslandModule.panelPossible
            && topIslandModule.popupState.isActive(topIslandModule.popupId)
        grabFocus: true

        implicitWidth: topIslandModule.popupWidth
        implicitHeight: popupContents.implicitHeight

        anchor {
            window: topIslandModule.topIsland
            adjustment: PopupAdjustment.Slide
        }

        onVisibleChanged: {
            if (!visible) {
                // Nothing to clear on the way out. `visible` is DERIVED from
                // the state's active id, so this window is hidden exactly when
                // that id stopped being its own — either Escape, an outside
                // click, or another widget taking this surface's one slot.
                // Clearing the slot here would be clearing a slot another
                // widget may already own.
                return;
            }
            popupContents.forceActiveFocus();
        }

        Rectangle {
            id: popupContents
            anchors.fill: parent

            focus: true
            Keys.onPressed: {
                if (event.key === Qt.Key_Escape && topIslandModule.popupState !== null) {
                    topIslandModule.popupState.close();
                }
            }

            color: UI.Colors.background
            border {
                color: UI.Colors.accent
                width: 1
            }

            implicitHeight: popupParentLayout.implicitHeight + (2 * topIslandModule.popupMargin)

            ColumnLayout {
                id: popupParentLayout
                anchors {
                    fill: parent
                    margins: topIslandModule.popupMargin
                }
                spacing: 0

                Loader {
                    id: popupContentLoader
                    Layout.fillWidth: true
                    sourceComponent: topIslandModule.popupContent
                    onLoaded: topIslandModule.makeChildrenUnfocusable(popupContentLoader.item)
                }
            }
        }
    }

    function updatePopupPosition() {
        if (!topIslandModule.topIsland || !popup) {
            return;
        }
        var pos = topIslandModule.topIsland.mapFromItem(topIslandModule, 0, 0);
        popup.anchor.rect = Qt.rect(pos.x + topIslandModule.implicitWidth / 2 - popup.implicitWidth / 2, topIslandModule.topIsland.implicitHeight + topIslandModule.popupTopIslandGap, popup.implicitWidth, popup.implicitHeight);
    }

    // Make all descendant items of the popup content non-focusable so that
    // interacting with them (e.g. sliders) does not steal focus from the
    // popup and trigger grabFocus dismissal.
    function makeChildrenUnfocusable(item) {
        if (!item) {
            return;
        }
        if ("focus" in item) {
            item.focus = false;
        }
        if ("activeFocusOnTab" in item) {
            item.activeFocusOnTab = false;
        }
        let kids = item.children;
        for (let i = 0; i < kids.length; i++) {
            topIslandModule.makeChildrenUnfocusable(kids[i]);
        }
    }
}
