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
    //
    // NOTE ON POPUP STATE (ticket 10)
    //
    //   There used to be a `popupStateManager` QtObject HERE — one for the
    //   whole shell, holding `activePopup` and `activeScreen`, handed to every
    //   panel widget on every monitor. Its `isActive(id, screen)` answered
    //   "active on any screen" to a caller that omitted the screen, and the
    //   network widget omitted it while the volume widget supplied it — so on a
    //   second monitor the network panel would have appeared on the monitor it
    //   was not opened from. Invisible with one monitor; wrong with two.
    //
    //   The state now lives in a PopupState INSIDE each delegate below, which
    //   is what makes it per-surface: the surface a widget lives in IS its
    //   monitor, so no widget passes one or can omit one. See
    //   components/PopupState.qml.
    //
    //   (This file is the pre-rewrite bar: ticket 08 took it out of shell.qml
    //   and ticket 18 deletes it. smoke.qml still compiles it, so the
    //   mechanism had to be fixed here rather than left to rot.)

    Variants {
        id: topIslandWindows
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

                // This surface's popup state, one per monitor. Opening a panel
                // on one monitor cannot open, close or shadow one on another,
                // and there is no monitor name anywhere for a widget to get
                // wrong.
                PopupState {
                    id: popupState
                }

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
                            popupState: popupState
                        }
                        BluetoothModule {}
                        VolumeModule {
                            topIsland: topIslandPanel
                            popupState: popupState
                        }
                        BatteryModule {}
                        NotificationModule {}
                    }
                }
            }
        }
    }
    // ===
}
