import Quickshell.Hyprland
import QtQuick

import "."
import "../ui" as UI

// Workspaces — Hyprland workspace indicators (ticket 15).
BarWidget {
    id: workspacesWidget

    tooltip: ""
    activate: function (widget) {}

    contentHandlesClicks: true

    // Read back in smoke for verification — independent of the binding logic.
    readonly property color occupiedWorkspaceColor: UI.Colors.foreground
    readonly property color emptyWorkspaceColor: UI.Colors.foregroundMuted

    content: Component {
        Row {
            spacing: 12

            Repeater {
                model: {
                    const active = Hyprland.workspaces.values.map(w => w.id)
                    const persistent = [1, 2, 3]
                    return [...new Set(persistent.concat(active))].sort((a, b) => a - b)
                }

                Text {
                    id: wsText

                    property int wsId: modelData
                    property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
                    property bool isActive: Hyprland.focusedWorkspace?.id === wsId

                    text: isActive ? "󱓻" : wsId

                    color: ws ? workspacesWidget.occupiedWorkspaceColor
                              : workspacesWidget.emptyWorkspaceColor

                    font {
                        family: UI.Fonts.fontFamily
                        pixelSize: UI.Fonts.fontSize
                        bold: false
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        onClicked: {
                            const target = Hyprland.workspaces.values.find(w => w.id === wsText.wsId)
                            if (target) {
                                target.activate()
                            }
                        }
                    }
                }
            }
        }
    }
}
