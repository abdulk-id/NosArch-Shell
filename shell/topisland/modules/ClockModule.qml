import QtQuick
import Quickshell
import "../../../components"

import "../../ui" as UI

Item {
    id: clockModule

    // UI ===
    implicitHeight: clockTextsRow.implicitHeight
    implicitWidth: clockTextsRow.implicitWidth

    Row {
        id: clockTextsRow
        spacing: 6
        anchors.centerIn: parent

        Text {
            id: clockTimeText
            anchors.verticalCenter: parent.verticalCenter

            text: clockModule.timeText
            color: UI.Colors.foreground
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
                bold: false
            }
        }
        Text {
            id: clockAmpmText
            anchors.verticalCenter: parent.verticalCenter

            text: clockModule.ampmText
            color: UI.Colors.accent
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSizeSmall
                bold: true
            }
        }

        Separator {
            separatorHeight: clockModule.implicitHeight
            separatorColor: UI.Colors.foregroundMuted
        }

        Text {
            id: clockDateText
            anchors.verticalCenter: parent.verticalCenter

            text: clockModule.dateText
            color: UI.Colors.foregroundMuted
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
                bold: false
            }
        }
    }

    // Behavior ===
    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }
    readonly property string timeText: Qt.formatDateTime(systemClock.date, "h:mm AP").replace(/ AM| PM/g, "")
    readonly property string ampmText: (systemClock.date.getHours() >= 12) ? "PM" : "AM"
    readonly property string dateText: Qt.formatDate(systemClock.date, "ddd MMMM d")

    // TODO: Time is still shown in 24hr format
}
