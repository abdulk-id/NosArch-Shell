import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            exclusionMode: PanelWindow.ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "nosarch-wallpaper"
            WlrLayershell.keyboardFocus: WlrLayershell.KeyboardFocus.None

            Image {
                anchors.fill: parent

                // Crop and center the image to fit the aspect ratio
                fillMode: Image.PreserveAspectCrop

                // Absolute path to your wallpaper file
                source: "file://" + Quickshell.env("HOME") + "/.local/share/nosarch/current-theme/current-wallpaper"
            }
        }
    }
}
