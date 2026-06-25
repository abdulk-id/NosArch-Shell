import Quickshell
import Quickshell.Services.UPower
import QtQuick

import "../../ui" as UI

Item {
    id: battery

    implicitWidth: batteryText.implicitWidth
    implicitHeight: batteryText.implicitHeight

    Text {
        id: batteryText

        text: {
            let battery = UPower.displayDevice;
            if (!battery || !battery.ready)
                return "󱉝"; // Loading/Not present

            let percentage = Math.round(battery.percentage * 100);
            let state = battery.state;

            let defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
            let chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"];

            // Icon index (0-9) based on percentage
            let iconIndex = Math.min(Math.floor(percentage / 10), 9);

            if (state === UPowerDeviceState.FullyCharged) {
                if (UPower.onBattery) {
                    return `${defaultIcons[iconIndex]} ${percentage}%`;
                } else {
                    return `${chargingIcons[iconIndex]} ${percentage}%`;
                }
            } else if (state === UPowerDeviceState.Charging) {
                return `${chargingIcons[iconIndex]} ${percentage}%`;
            } else if (state === UPowerDeviceState.PendingCharge) {
                // Check if plugged but not necessarily charging
                return ` ${percentage}%`;
            }
            // Default discharging state
            return `${defaultIcons[iconIndex]} ${percentage}%`;
        }
        color: {
            let percentage = Math.round(UPower.displayDevice.percentage * 100);
            if (percentage <= 10) {
                return "#ff5555"; // critical
            } else if (percentage <= 20) {
                return "#ffb86c"; // warning
            }
            return UI.Colors.foreground; // default/good
        }
        font {
            family: UI.Fonts.fontFamily
            pixelSize: UI.Fonts.fontSize
        }
    }

    MouseArea {
        id: batteryMouseArea

        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: Quickshell.execDetached(["sh", "-c", "vicinae vicinae://launch/@botkooper/store.vicinae.power-profile/power-profile"])
    }
}
