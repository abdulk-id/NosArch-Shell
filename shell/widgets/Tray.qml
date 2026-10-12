import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import "."

// Tray — status notifier icons (ticket 15).
//
// Menu anchoring and three-button handling are carried forward from the
// pre-rewrite SystemTrayModule unchanged.
BarWidget {
    id: trayWidget

    tooltip: ""
    activate: function (widget) {}

    contentHandlesClicks: true

    readonly property string trayAcceptedButtons: "left|right|middle"
    readonly property string trayMenuAnchorKind: "QsMenuAnchor"

    content: Component {
        Row {
            spacing: 20

            Repeater {
                model: SystemTray.items

                Item {
                    id: trayItem
                    required property SystemTrayItem modelData

                    width: 20
                    height: 20

                    IconImage {
                        anchors.centerIn: parent
                        source: {
                            const icon = trayItem.modelData.icon

                            if (icon === "") {
                                return ""
                            }

                            if (icon.startsWith("/") || icon.startsWith("file:") || icon.startsWith("image:")
                                    || icon.startsWith("qrc:") || icon.startsWith("data:")) {
                                return icon
                            }

                            return "image://icon/" + encodeURIComponent(icon)
                        }
                        asynchronous: true
                        mipmap: true
                        implicitSize: 16
                    }

                    QsMenuAnchor {
                        id: menuAnchor
                        menu: trayItem.modelData.menu

                        anchor.window: trayItem.QsWindow.window
                        anchor.adjustment: PopupAdjustment.Flip

                        anchor.onAnchoring: {
                            const window = trayItem.QsWindow.window
                            menuAnchor.anchor.rect = window.contentItem.mapFromItem(
                                trayItem, 0, trayItem.height, trayItem.width, trayItem.height)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        hoverEnabled: true

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                modelData.activate()
                            } else if (mouse.button === Qt.RightButton) {
                                if (modelData.hasMenu) {
                                    menuAnchor.open()
                                }
                            } else if (mouse.button === Qt.MiddleButton) {
                                modelData.secondaryActivate()
                            }
                        }
                    }
                }
            }
        }
    }
}
