import QtQuick

import "../../ui" as UI
import "../../../services" as Services

Item {
    id: playerModule

    implicitHeight: playerText.implicitHeight
    implicitWidth: playerText.implicitWidth

    Text {
        id: playerText

        text: {
            if (!Services.Media.isAvailable) {
                return "";
            }

            if (Services.Media.isPlaying) {
                return Services.Media.getPlayerIcon();
            } else if (Services.Media.isPaused) {
                return "";
            } else if (Services.Media.isStopped) {
                return "";
            } else {
                return "";
            }
        }
        color: UI.Colors.foreground
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSizeIcons
        }

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        cursorShape: Qt.PointingHandCursor

        onClicked: {
            Services.Media.togglePlayPause();
        }
    }
}
