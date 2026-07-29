pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: systemInfo

    // API
    property alias cpu: cpuObject
    property alias memory: memoryObject
    property alias battery: batteryObject

    // CPU Usage
    QtObject {
        id: cpuObject

        property int usagePercent: 0
    }
    Scope {
        id: cpuScope

        property int previousIdleTicks: 0
        property int previousTotalTicks: 0

        Process {
            id: cpuProcess

            command: ["sh", "-c", "head -1 /proc/stat"]
            // Command example output: `cpu  4705 0 1960 136239 173 0 107 0 0 0`
            // Field names: `user nice system idle iowait irq softirq steal guest guest_nice`

            stdout: SplitParser {
                onRead: data => {
                    if (!data) {
                        return;
                    }

                    // Math done by ChatGPT
                    const fields = data.trim().split(/\s+/);

                    const currentIdleTicks = parseInt(fields[4]) + parseInt(fields[5]); // idle + iowait
                    const currentTotalTicks = fields.slice(1, 8).reduce((a, b) => a + parseInt(b), 0);

                    if (cpuScope.previousTotalTicks > 0) {
                        const totalDelta = currentTotalTicks - cpuScope.previousTotalTicks;
                        const idleDelta = currentIdleTicks - cpuScope.previousIdleTicks;

                        if (totalDelta > 0) {
                            // Guard against division by zero
                            cpuObject.usagePercent = Math.round(100 * (1 - idleDelta / totalDelta));
                        }
                    }

                    cpuScope.previousTotalTicks = currentTotalTicks;
                    cpuScope.previousIdleTicks = currentIdleTicks;
                }
            }

            Component.onCompleted: running = true
        }
    }

    // Memory Usage
    QtObject {
        id: memoryObject

        property real totalGib: 0
        property real availableGib: 0
        property int usagePercent: 0
    }
    Process {
        id: memProcess

        command: ["sh", "-c", "cat /proc/meminfo"]

        stdout: SplitParser {
            onRead: data => {
                if (!data) {
                    return;
                }

                const [key, value] = data.trim().split(/\s+/);
                const valueKiB = parseInt(value);

                if (key === "MemTotal:") {
                    memoryObject.totalGib = valueKiB / 1024 / 1024;
                } else if (key === "MemAvailable:") {
                    memoryObject.availableGib = valueKiB / 1024 / 1024;
                }

                if (memoryObject.totalGib > 0) {
                    memoryObject.usagePercent = Math.round(100 * (1 - memoryObject.availableGib / memoryObject.totalGib));
                }
            }
        }

        Component.onCompleted: running = true
    }

    // Battery Info
    QtObject {
        id: batteryObject

        readonly property var battery: UPower.displayDevice
        readonly property bool present: battery && battery.ready

        readonly property int percentage: present ? Math.round(battery.percentage * 100) : 0
        readonly property bool charging: present && battery.state === UPowerDeviceState.Charging
        readonly property bool fullyCharged: present && battery.state === UPowerDeviceState.FullyCharged
        readonly property bool pendingCharge: present && battery.state === UPowerDeviceState.PendingCharge

        readonly property var defaultIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        readonly property var chargingIcons: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
        readonly property string textIcon: {
            if (!batteryObject.present) {
                return "󱉝";
            }

            let iconIndex = Math.min(Math.floor(percentage / 10), 9);

            if (batteryObject.fullyCharged) {
                if (UPower.onBattery) {
                    return defaultIcons[iconIndex];
                } else {
                    return chargingIcons[iconIndex];
                }
            } else if (batteryObject.charging) {
                return chargingIcons[iconIndex];
            } else if (batteryObject.pendingCharge) {
                return "";
            }

            return defaultIcons[iconIndex];
        }
    }

    // Update Timer
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            cpuProcess.running = true;
            memProcess.running = true;
        }
    }
}
