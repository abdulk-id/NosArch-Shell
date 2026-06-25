import QtQuick
import QtQuick.Layouts

import "../shell/ui" as UI

Rectangle {
    id: progressOsdItem

    required property int value
    required property string text
    required property string fontIcon
    required property bool osdVisible

    required property string accessibleName

    implicitWidth: 50
    implicitHeight: 200
    radius: 10
    color: UI.Colors.background
    border.width: 1
    border.color: UI.Colors.accent

    opacity: progressOsdItem.osdVisible ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    ColumnLayout {
        anchors {
            fill: parent

            topMargin: 10
            bottomMargin: 10
            leftMargin: 0
            rightMargin: 0
        }

        spacing: 10

        Text {
            Layout.alignment: Qt.AlignHCenter

            text: progressOsdItem.text

            color: UI.Colors.foreground

            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSize
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true

            Layout.preferredWidth: 5
            radius: 4
            color: "#50ffffff"

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                height: Math.min(parent.height * (progressOsdItem.value / 100), parent.height)

                radius: parent.radius
                color: UI.Colors.accent

                Behavior on height {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter

            text: progressOsdItem.fontIcon

            color: UI.Colors.foreground

            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSizeIcons
            }
        }
    }

    Accessible.role: Accessible.ProgressBar
    Accessible.name: progressOsdItem.accessibleName
}
