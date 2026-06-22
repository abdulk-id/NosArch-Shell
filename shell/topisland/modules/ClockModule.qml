import QtQuick
import Quickshell
import Quickshell.Wayland
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

    // UI.Calender Popup === (Copied from Anomshell)
    //TODO: Proper location (top/bottom margin) calculation, not hardcoded
    PanelWindow {
        id: calendarWindow

        property bool showing: false

        color: "transparent"
        visible: true

        anchors {
            // Top center
            top: true
        }
        margins {
            // Distance from screen borders
            top: 44
        }
        implicitWidth: 250
        implicitHeight: showing ? calendarColumn.implicitHeight + 20 : 0
        exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Behavior on implicitHeight {
            NumberAnimation {
                // Adds a sliding in/out animation
                duration: 15
                easing.type: Easing.OutCubic
            }
        }

        property int viewYear: new Date().getFullYear()
        property int viewMonth: new Date().getMonth()
        property var today: new Date()

        function daysInMonth(y, m) {
            return new Date(y, m + 1, 0).getDate();
        }
        function firstDayOfMonth(y, m) {
            const d = new Date(y, m, 1).getDay();
            return (d + 6) % 7;
        }
        function prevMonth() {
            if (viewMonth === 0) {
                viewMonth = 11;
                viewYear--;
            } else
                viewMonth--;
        }
        function nextMonth() {
            if (viewMonth === 11) {
                viewMonth = 0;
                viewYear++;
            } else
                viewMonth++;
        }

        Rectangle {
            anchors.fill: parent

            color: UI.Colors.background
            radius: 10

            clip: true
            opacity: calendarWindow.showing ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    // Adds a fade animation
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: calHover
                anchors.fill: parent
                hoverEnabled: true
                onEntered: hideTimer.stop()
                onExited: hideTimer.start()
            }

            Column {
                id: calendarColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                // Month Header (Current month and year + buttons for switching months)
                Row {
                    width: parent.width
                    height: 20

                    // Button to go to previous month
                    Text {
                        text: "‹"

                        color: UI.Colors.foregroundMuted
                        font.pixelSize: UI.Fonts.fontSize
                        font.family: UI.Fonts.fontFamily

                        width: 20
                        horizontalAlignment: Text.AlignHCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendarWindow.prevMonth()
                        }
                    }

                    // Current month and year
                    Text {
                        text: {
                            const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
                            return months[calendarWindow.viewMonth] + " " + calendarWindow.viewYear;
                        }

                        color: UI.Colors.foreground
                        font.pixelSize: UI.Fonts.fontSizeSmall
                        font.family: UI.Fonts.fontFamily
                        font.weight: Font.Medium

                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // Button to go to next month
                    Text {
                        text: "›"

                        color: UI.Colors.foregroundMuted
                        font.pixelSize: UI.Fonts.fontSize
                        font.family: UI.Fonts.fontFamily

                        width: 20
                        horizontalAlignment: Text.AlignHCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendarWindow.nextMonth()
                        }
                    }
                }

                // Day labels
                Row {
                    width: parent.width
                    //spacing: 0
                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            text: modelData

                            color: UI.Colors.foregroundMuted
                            font.pixelSize: UI.Fonts.fontSizeSmall
                            font.family: UI.Fonts.fontFamily

                            width: calendarColumn.width / 7
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Month days grid
                Grid {
                    id: dayGrid
                    columns: 7
                    width: parent.width
                    spacing: 0

                    Behavior on opacity {
                        NumberAnimation {
                            // TODO: Not sure what this animation does
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }

                    Repeater {
                        model: {
                            const offset = calendarWindow.firstDayOfMonth(calendarWindow.viewYear, calendarWindow.viewMonth);
                            const days = calendarWindow.daysInMonth(calendarWindow.viewYear, calendarWindow.viewMonth);
                            return offset + days;
                        }

                        Item {
                            width: dayGrid.width / 7
                            height: 22

                            readonly property int dayNum: index - calendarWindow.firstDayOfMonth(calendarWindow.viewYear, calendarWindow.viewMonth) + 1
                            readonly property bool isValid: index >= calendarWindow.firstDayOfMonth(calendarWindow.viewYear, calendarWindow.viewMonth)
                            readonly property bool isToday: isValid && dayNum === calendarWindow.today.getDate() && calendarWindow.viewMonth === calendarWindow.today.getMonth() && calendarWindow.viewYear === calendarWindow.today.getFullYear()

                            // Accent-colored Dot on current day
                            Rectangle {
                                anchors.centerIn: parent
                                color: isToday ? (UI.Colors.accent) : "transparent"

                                width: 20
                                height: 20
                                radius: 10

                                visible: isValid
                            }

                            // Days of month text
                            Text {
                                text: isValid ? dayNum : ""

                                color: isToday ? (UI.Colors.background) : (UI.Colors.foreground)
                                font.pixelSize: UI.Fonts.fontSizeSmall
                                font.family: UI.Fonts.fontFamily
                                font.weight: isToday ? Font.Bold : Font.Normal

                                opacity: isValid ? 1.0 : 0.0

                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: calendarWindow.showing = true
        onExited: hideTimer.start()
    }
    // ===

    // Behavior ===
    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }
    //readonly property string currentTime: Qt.formatDateTime(systemClock.date, "h:mm AP | ddd MMMM d")
    readonly property string timeText: String(systemClock.date.getHours()) + ":" + String(systemClock.date.getMinutes()).padStart(2, "0")
    readonly property string ampmText: (systemClock.date.getHours() >= 12) ? "PM" : "AM"
    readonly property string dateText: Qt.formatDate(systemClock.date, "ddd MMMM d")

    // TODO: Time is still shown in 24hr format

    // Calendar window behavior
    Timer {
        id: hideTimer
        interval: 300
        onTriggered: {
            if (!calHover.containsMouse) {
                calendarWindow.showing = false;
            }
        }
    }
    // ===
}
