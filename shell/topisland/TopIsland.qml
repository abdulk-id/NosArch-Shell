import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "modules"
import "../../components"

import "../ui" as UI

Scope {
    id: topisland
    // UI Properties ===
    property int barHeight: 35
    property int itemSpacing: 35
    property int trayIconSize: 16

    property bool isFloating: true
    property int barMagins: isFloating ? 5 : 0
    property int barCornerRadius: isFloating ? 10 : 0
    // ===

    // UI ===
    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                // For separate bar on each screen
                required property var modelData
                screen: modelData

                focusable: false
                WlrLayershell.namespace: "nosarch-top-island"
                WlrLayershell.layer: WlrLayer.Top

                anchors {
                    top: true
                    left: true
                    right: true
                }
                margins.top: topisland.barMagins
                margins.left: topisland.barMagins
                margins.right: topisland.barMagins

                implicitHeight: topisland.barHeight

                color: "transparent"

                Rectangle {
                    id: panelArea

                    anchors.fill: parent
                    radius: topisland.barCornerRadius

                    color: UI.Colors.background

                    // Left modules
                    RowLayout {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 20

                        ArchIconModule {}
                        Workspaces {}

                        Separator {
                            separatorHeight: panel.implicitHeight - 10 //TODO: Proper height calculation, not hardcoded
                            separatorColor: UI.Colors.foregroundMuted
                        }

                        // Resource usage modules
                        CpuUsageModule {}
                        MemoryUsageModule {}
                    }

                    // Center modules
                    Item {
                        anchors.fill: parent

                        RowLayout { // Modules to left of clock
                            anchors {
                                right: clock.left
                                verticalCenter: parent.verticalCenter

                                leftMargin: 15
                                rightMargin: 15
                            }
                            spacing: 20

                            PlayerModule {}
                        }
                        ClockModule {
                            id: clock
                            anchors.centerIn: parent
                        }
                    }

                    // Right modules
                    RowLayout {
                        anchors {
                            right: parent.right
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 25

                        SystemTrayModule {}

                        Separator {
                            separatorHeight: panel.implicitHeight - 10 //TODO: Proper height calculation, not hardcoded
                            separatorColor: UI.Colors.foregroundMuted
                        }

                        NetworkModule {}
                        BluetoothModule {}
                        VolumeModule {}
                        BatteryModule {}
                        NotificationModule {}
                    }
                }
            }
        }
    }
    // ===
}
