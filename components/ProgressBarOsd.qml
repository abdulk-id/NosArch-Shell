import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import "../shell/ui" as UI

Scope {
    id: progressBarOsd

    required property int value
    required property string fontIcon

    required property bool osdVisible

    // UI ===
    LazyLoader {
        active: progressBarOsd.osdVisible

        PanelWindow {
            anchors {
                right: true
            }

            margins.right: 10
            exclusiveZone: 0

            implicitWidth: 50
            implicitHeight: 200

            color: "transparent"

            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: UI.Colors.background

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Text {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                        text: progressBarOsd.value + "%"

                        color: UI.Colors.foreground

                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeSmall
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        Layout.fillHeight: true

                        Layout.preferredWidth: 5
                        radius: 20
                        color: "#50ffffff"

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }

                            height: Math.min(parent.height * (progressBarOsd.value / 100), parent.height)

                            radius: parent.radius
                            color: UI.Colors.accent ?? "white"
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                        text: progressBarOsd.fontIcon

                        color: UI.Colors.foreground

                        font {
                            family: UI.Fonts.fontFamily
                            pixelSize: UI.Fonts.fontSizeIcons
                        }
                    }
                }
            }
        }
    }
}
