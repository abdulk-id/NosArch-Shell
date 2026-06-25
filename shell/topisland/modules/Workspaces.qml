import Quickshell.Hyprland
import QtQuick

import "../../ui" as UI

Item {
    id: workspacesModule

    implicitHeight: workspaces.implicitHeight
    implicitWidth: workspaces.implicitWidth

    Row {
        id: workspaces

        spacing: 12

        Repeater {
            model: {
                let active = Hyprland.workspaces.values.map(w => w.id); // Active workspace IDs (that have windows)
                let persistent = [1, 2, 3]; // Always include 1, 2, 3
                let result = [...new Set(persistent.concat(active))].sort((a, b) => a - b); // Merge + deduplicate + sort

                return result;
            }

            Text {
                id: wsText

                property int wsId: modelData
                property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
                property bool isActive: Hyprland.focusedWorkspace?.id === wsId

                text: isActive ? "󱓻" : wsId

                color: ws ? UI.Colors.foreground : UI.Colors.foregroundMuted

                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSize
                    bold: false
                }

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: wsText.ws?.activate()
                }
            }
        }
    }
}
