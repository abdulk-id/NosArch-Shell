import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: systemTrayModule

    implicitWidth: systemTrayRow.implicitWidth

    Row {
        id: systemTrayRow
        spacing: 20
        anchors.centerIn: parent

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
                        const icon = trayItem.modelData.icon;

                        if (icon === "") {
                            return "";
                        }

                        if (icon.startsWith("/") || icon.startsWith("file:") || icon.startsWith("image:") || icon.startsWith("qrc:") || icon.startsWith("data:")) {
                            return icon;
                        }

                        return "image://icon/" + encodeURIComponent(icon);
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
                        const window = trayItem.QsWindow.window;
                        menuAnchor.anchor.rect = window.contentItem.mapFromItem(trayItem, 0, trayItem.height, trayItem.width, trayItem.height);
                    }
                }

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    hoverEnabled: true

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            modelData.activate();
                        } else if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu) {
                                menuAnchor.open();
                            }
                        } else if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate();
                        }
                    }
                }
            }
        }
    }
}
