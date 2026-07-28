import QtQuick
import Quickshell
import Quickshell.Wayland

import "../../components"

Scope {
    VolumeOsd {
        id: volumeOsd
    }
    BrightnessOsd {
        id: brightnessOsd
    }
    KeyboardBrightnessOsd {
        id: keyboardBrightnessOsd
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            visible: volumeOsd.osdVisible || brightnessOsd.osdVisible || keyboardBrightnessOsd.osdVisible
            focusable: false
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "nosarch-osd"

            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            anchors {
                right: true
                top: true
                bottom: true
            }

            implicitWidth: 70

            Column {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                ProgressOSDItem {
                    value: volumeOsd.currentVolume
                    text: volumeOsd.text
                    fontIcon: volumeOsd.fontIcon
                    osdVisible: volumeOsd.osdVisible

                    accessibleName: volumeOsd.accessibleName
                }
                ProgressOSDItem {
                    value: brightnessOsd.currentBrightness
                    text: brightnessOsd.text
                    fontIcon: brightnessOsd.fontIcon
                    osdVisible: brightnessOsd.osdVisible

                    accessibleName: brightnessOsd.accessibleName
                }
                ProgressOSDItem {
                    value: keyboardBrightnessOsd.currentBrightness
                    text: keyboardBrightnessOsd.text
                    fontIcon: keyboardBrightnessOsd.fontIcon
                    osdVisible: keyboardBrightnessOsd.osdVisible
                    visible: keyboardBrightnessOsd.available

                    accessibleName: keyboardBrightnessOsd.accessibleName
                }
            }
        }
    }
}
