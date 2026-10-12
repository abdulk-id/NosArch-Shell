import QtQuick
import Quickshell

import "."
import "../ui" as UI

// Launcher — opens the existing NosArch application launcher (ticket 15).
BarWidget {
    id: launcher

    tooltip: "Application launcher"

    readonly property string launcherCommand: "nosarch-launcher"

    activate: function (widget) {
        Quickshell.execDetached(["sh", "-c", launcher.launcherCommand])
    }

    content: Component {
        Text {
            text: ""
            color: UI.Colors.accent
            font {
                family: UI.Fonts.fontFamily
                pixelSize: UI.Fonts.fontSizeIcons
            }
        }
    }
}
