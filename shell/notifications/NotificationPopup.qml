import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

import "../ui" as UI
import "../../services"

Scope {
    id: root

    // UI Properties
    readonly property int popupMargin: 5
    readonly property int contentPadding: 10
    // ===

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notifWindow
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "nosarch-shell-notifications"

            exclusionMode: ExclusionMode.Auto

            anchors {
                top: true
                right: true
            }

            implicitWidth: 380
            implicitHeight: notifColumn.implicitHeight + 20

            focusable: false
            color: "transparent"

            ColumnLayout {
                id: notifColumn

                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 10
                    rightMargin: 10
                }
                width: 360
                spacing: 8

                Repeater {
                    model: ScriptModel {
                        values: NotificationService.notifications
                        objectProp: "seqId"
                    }

                    Rectangle {
                        id: notifPopup
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: popupContent.implicitHeight + root.popupMargin * 2

                        color: UI.Colors.background
                        radius: 12
                        border {
                            width: 1
                            color: modelData.urgency === NotificationUrgency.Critical ? UI.Colors.alertRed : UI.Colors.accent
                        }
                        clip: true

                        Accessible.role: Accessible.StaticText
                        Accessible.name: (modelData.urgency === NotificationUrgency.Critical ? "[Critical] " : modelData.urgency === NotificationUrgency.Low ? "[Low] " : "") + (modelData.appName || "Notification") + ": " + modelData.summary

                        HoverHandler {
                            id: cardHover
                            onHoveredChanged: notifPopup.modelData.hovered = hovered
                        }

                        NumberAnimation on opacity {
                            id: entryAnim
                            from: 0
                            to: 1
                            duration: 200
                            easing.type: Easing.OutCubic
                            running: false
                        }
                        Component.onCompleted: entryAnim.start()

                        // Popup content
                        RowLayout {
                            id: popupContent

                            anchors {
                                fill: parent
                                leftMargin: root.popupMargin
                                rightMargin: root.popupMargin
                                topMargin: root.popupMargin
                                bottomMargin: root.popupMargin
                            }

                            spacing: 0

                            // App icon
                            IconImage {
                                id: notifAppIcon

                                Layout.preferredWidth: implicitSize
                                Layout.preferredHeight: implicitSize
                                Layout.alignment: Qt.AlignVCenter

                                Layout.margins: root.contentPadding

                                source: Quickshell.iconPath(notifPopup.modelData.appIcon, true)
                                implicitSize: 48

                                visible: notifPopup.modelData.appIcon !== ""
                            }

                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.margins: root.contentPadding

                                spacing: 2

                                // Container for App Name and Close Button
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // App Name
                                    Text {
                                        id: notifAppName

                                        Layout.alignment: Qt.AlignVCenter

                                        text: notifPopup.modelData.appName || "Notification"
                                        color: UI.Colors.foregroundSecondary
                                        font {
                                            family: UI.Fonts.fontFamily
                                            pixelSize: UI.Fonts.fontSizeSmall
                                        }
                                    }

                                    // Add gap between name and close button
                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    // Close button
                                    Rectangle {
                                        id: closeButton

                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20

                                        color: closeHover.containsMouse ? UI.Colors.backgroundHover : "transparent"
                                        radius: 10

                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Dismiss notification"

                                        // Close button icon text
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: closeHover.containsMouse ? UI.Colors.foreground : UI.Colors.foregroundMuted
                                            font {
                                                family: UI.Fonts.fontFamily
                                                pixelSize: UI.Fonts.fontSizeIcons
                                            }
                                        }

                                        MouseArea {
                                            id: closeHover

                                            anchors.fill: parent

                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: notifPopup.modelData.dismiss()
                                        }
                                    }
                                }

                                // Notification summary text
                                Text {
                                    id: notifSummaryText

                                    Layout.fillWidth: true

                                    text: notifPopup.modelData.summary
                                    color: UI.Colors.foreground
                                    font {
                                        family: UI.Fonts.fontFamily
                                        pixelSize: UI.Fonts.fontSize
                                        bold: true
                                    }
                                    elide: Text.ElideRight

                                    visible: text !== ""
                                }

                                // TODO: The unknown component
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Notification body text
                                    Text {
                                        id: notifBodyText

                                        Layout.fillWidth: true

                                        text: notifPopup.modelData.body
                                        textFormat: Text.PlainText
                                        color: UI.Colors.foreground
                                        font {
                                            family: UI.Fonts.fontFamily
                                            pixelSize: UI.Fonts.fontSizeSmall
                                        }
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight

                                        visible: text !== ""
                                    }

                                    // TODO: Unknown component
                                    Rectangle {
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24

                                        radius: 4
                                        color: "transparent"
                                        clip: true

                                        Image {
                                            anchors.fill: parent

                                            source: notifPopup.modelData.image

                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize.width: 24
                                            sourceSize.height: 24
                                        }

                                        visible: notifPopup.modelData.image !== ""
                                    }

                                    visible: notifPopup.modelData.body !== "" || notifPopup.modelData.image !== ""
                                }

                                // Action buttons
                                RowLayout {
                                    id: actionButtonRow

                                    Layout.fillWidth: true

                                    spacing: 6

                                    Repeater {
                                        model: notifPopup.modelData.actions

                                        Rectangle {
                                            id: actionButton
                                            required property var modelData

                                            Layout.preferredHeight: 26
                                            Layout.preferredWidth: actionButtonText.width + 16

                                            color: actionButtonHover.containsMouse ? UI.Colors.backgroundHover : UI.Colors.backgroundSurface
                                            radius: 6

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 100
                                                }
                                            }

                                            Accessible.role: Accessible.Button
                                            Accessible.name: actionButton.modelData.text || ""

                                            Text {
                                                id: actionButtonText

                                                anchors.centerIn: parent

                                                text: actionButton.modelData.text || ""
                                                color: UI.Colors.accent
                                                font {
                                                    family: UI.Fonts.fontFamily
                                                    pixelSize: UI.Fonts.fontSizeSmall
                                                }
                                            }

                                            MouseArea {
                                                id: actionButtonHover
                                                anchors.fill: parent

                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor

                                                onClicked: notifPopup.modelData.invokeAction(actionButton.modelData.identifier)
                                            }
                                        }
                                    }

                                    visible: notifPopup.modelData.actions.length > 0
                                }
                            }
                        }

                        // Click on the notification to dismiss
                        MouseArea {
                            id: notifMouseArea

                            anchors.fill: parent
                            anchors.topMargin: 30 //TODO: What is this for?

                            z: -1

                            cursorShape: Qt.PointingHandCursor

                            onClicked: notifPopup.modelData.dismiss()
                        }
                    }
                }
            }

            visible: NotificationService.notifications.length > 0
        }
    }
}

/* UI Structure (ignoring repeaters and variants)
root {Scope}
└── notifWindow {PanelWindow}
    └── notifColumn {ColumnLayout} (for laying out 5 popups on top of each other, uses repeater)
        ├── notifPopup {Rectangle} (the actual notification popup)
        │   └── popupContent {RowLayout} (for laying out the popup content)
        │       ├── notifAppIcon {IconImage} (the notification app icon)
        │       └── {ColumnLayout} (for laying out the notification text and action buttons)
        │           ├── {RowLayout} (for app name and close button)
        │           │   ├── notifAppName {Text} (the app name)
        │           │   └── closeButton {Rectangle} (the close button)
        │           ├── notifSummaryText {Text} (the notification summary text)
        │           ├── {RowLayout}
        │           │   ├── notifBodyText {Text} (the notification body text)
        │           │   └── {Rectangle} (TODO: Unknown Component)
        │           │       └── {Image}
        │           └── actionButtonRow {RowLayout} (for laying out the action buttons, uses repeater)
        │               └── actionButton {Rectangle} (the action button)
        │                   ├── actionButtonText {Text} (the action button text)
        │                   └── actionButtonHover {MouseArea} (the action button hover area)
        └── notifMouseArea {MouseArea} (the notification mouse area, to dismiss on click)
*/
