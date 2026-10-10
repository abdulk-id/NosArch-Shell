import QtQuick
import QtQuick.Layouts
import Quickshell

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
    property QtObject popupState
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
            if (topIslandModule.hasPopup && topIslandModule.popupState && topIslandModule.popupId && topIslandModule.topIsland) {
                let screen = topIslandModule.topIsland.screen.name;
                if (topIslandModule.popupState.isActive(topIslandModule.popupId, screen)) {
                    topIslandModule.popupState.close();
                } else {
                    topIslandModule.popupState.set(topIslandModule.popupId, screen);
                    topIslandModule.updatePopupPosition();
                    if (popup) {
                        popup.anchor.updateAnchor();
                    }
                }
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
        visible: topIslandModule.hasPopup && topIslandModule.popupState && topIslandModule.topIsland && topIslandModule.popupState.isActive(topIslandModule.popupId, topIslandModule.topIsland.screen.name)
        grabFocus: true

        implicitWidth: topIslandModule.popupWidth
        implicitHeight: popupContents.implicitHeight

        anchor {
            window: topIslandModule.topIsland
            adjustment: PopupAdjustment.Slide
        }

        onVisibleChanged: {
            if (visible) {
                popupContents.forceActiveFocus();
            } else if (topIslandModule.popupState && topIslandModule.topIsland && topIslandModule.popupState.isActive(topIslandModule.popupId, topIslandModule.topIsland.screen.name)) {
                topIslandModule.popupState.close();
            }
        }

        Rectangle {
            id: popupContents
            anchors.fill: parent

            focus: true
            Keys.onPressed: {
                if (event.key === Qt.Key_Escape) {
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
