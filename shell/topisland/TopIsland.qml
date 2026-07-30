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
    QtObject {
        id: popupStateManager

        property string activePopup: ""

        function set(id) {
            activePopup = id;
        }
        function close() {
            activePopup = "";
        }
        function isActive(id) {
            return activePopup === id;
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: topIslandPanel

                required property var modelData
                screen: modelData

                focusable: false
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "nosarch-shell-top-island"

                anchors {
                    top: true
                    left: true
                    right: true
                }

                implicitHeight: topisland.barHeight

                margins {
                    top: topisland.barMagins
                    left: topisland.barMagins
                    right: topisland.barMagins
                }

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
                            separatorHeight: topIslandPanel.implicitHeight - 10 //TODO: Proper height calculation, not hardcoded
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
                            separatorHeight: topIslandPanel.implicitHeight - 10 //TODO: Proper height calculation, not hardcoded
                            separatorColor: UI.Colors.foregroundMuted
                        }

                        NetworkModule {
                            topIsland: topIslandPanel
                            popupState: popupStateManager
                        }
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
