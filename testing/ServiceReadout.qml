// ServiceReadout.qml — a DEVELOPMENT READOUT PANEL, not a test.
//
// It renders live service values in a side panel for poking at a service by
// eye. It asserts nothing, it exits 0 no matter what fails, and it is run by
// no verification script — do not read its exit code as a result. (It was
// named ServiceTest.qml, which invited exactly that reading: it emitted
// ~13 WARN TypeErrors on every launch and still exited 0.)
//
// Verification lives in smoke.qml (run it through
// scripts/verify-smoke.sh), which instantiates every widget, service and
// component and fails on QML errors. The readout value of this panel is
// duplicated there as the per-service PASS lines, which print live values
// without needing a panel on screen.
//
//   quickshell -p testing/ServiceReadout.qml
//
// Expect transient "property of undefined" values here while the singletons
// populate — that is this harness binding sub-objects early, not a defect to
// chase (the pre-rewrite baseline record documents this in full).

import QtQuick
import Quickshell
import Quickshell.Wayland

import "../services" as Services

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "nosarch-shell-service-test"

    anchors {
        right: true
        top: true
        bottom: true
    }

    implicitWidth: 280
    color: "#cc1e1e1e"

    Rectangle {
        anchors.fill: parent
        color: "#202020"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            function row(label, value) {
                return `${label}: ${value}`;
            }

            Text {
                color: "white"
                font.bold: true
                text: "System Info"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("CPU Usage", Services.SystemInfo.cpu.usagePercent + "%")
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Memory Usage", Services.SystemInfo.memory.usagePercent + "%")
            }

            Text {
                color: "white"
                text: parent.row("Memory Total", Services.SystemInfo.memory.totalGib.toFixed(2) + " GiB")
            }

            Text {
                color: "white"
                text: parent.row("Memory Available", Services.SystemInfo.memory.availableGib.toFixed(2) + " GiB")
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Battery Present", Services.SystemInfo.battery.present)
            }

            Text {
                color: "white"
                text: parent.row("Battery %", Services.SystemInfo.battery.percentage + "%")
            }

            Text {
                color: "white"
                text: parent.row("Charging", Services.SystemInfo.battery.charging)
            }

            Text {
                color: "white"
                text: parent.row("Fully Charged", Services.SystemInfo.battery.fullyCharged)
            }

            Text {
                color: "white"
                text: parent.row("Pending Charge", Services.SystemInfo.battery.pendingCharge)
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Network Device Wired", Services.NetworkService.isActiveDeviceWired)
            }

            Text {
                color: "white"
                text: parent.row("Network Device Wireless", Services.NetworkService.isActiveDeviceWireless)
            }

            Text {
                color: "white"
                text: parent.row("Active Network name", Services.NetworkService.activeNetwork.name)
            }

            Text {
                color: "white"
                font.family: "JetbrainsMono Nerd Font"
                text: parent.row("Network Icon", Services.NetworkService.textIcon)
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#505050"
            }

            Text {
                color: "white"
                text: parent.row("Bluetooth adapter",
                    Services.BluetoothService.defaultAdapter ? "present" : "absent")
            }

            Text {
                color: "white"
                text: parent.row("Bluetooth connected device",
                    Services.BluetoothService.hasDeviceConnected)
            }
        }
    }
}
