import QtQuick

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: notificationModule

    implicitHeight: notificationText.implicitHeight
    implicitWidth: notificationText.implicitWidth

    Text {
        id: notificationText

        text: Services.NotificationService.doNotDisturb ? "" : ""
        color: Services.NotificationService.doNotDisturb ? UI.Colors.accent : UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }
    MouseArea {
        id: memUsageMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Services.NotificationService.doNotDisturb = !Services.NotificationService.doNotDisturb
    }
}
