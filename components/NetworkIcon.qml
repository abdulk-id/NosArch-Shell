import QtQuick
import Quickshell.Networking

import "../services" as Services

// NetworkIcon — network presentation in one place (ticket 12, ADR 0001).
//
// Reads state from NetworkService and Networking; never decides policy, only
// how that state should look on screen.

QtObject {
    id: icon

    readonly property var service: Services.NetworkService

    readonly property bool hasDevice: icon.service.activeDevice !== null
    readonly property bool isWireless: icon.service.isActiveDeviceWireless
    readonly property bool isWired: icon.service.isActiveDeviceWired

    readonly property int connectivity: Networking.connectivity
    readonly property bool wifiEnabled: Networking.wifiEnabled

    readonly property real signalStrength: {
        const net = icon.service.activeNetwork
        return net ? net.signalStrength : 0
    }

    readonly property string glyph: icon.glyphFor(
        icon.connectivity,
        icon.hasDevice ? (icon.isWireless ? 1 : 2) : 0,
        icon.signalStrength,
        icon.hasDevice,
        icon.service.activeNetwork !== null)

    // deviceKind: 0 = none, 1 = wifi, 2 = wired — for tests without live hardware.
    function glyphFor(connectivity, deviceKind, signalStrength, hasDevice, hasActiveNetwork): string {
        if (!hasDevice) {
            if (connectivity === NetworkConnectivity.None) {
                return "󰤮"
            }
            return "󰤫"
        }

        if (connectivity === NetworkConnectivity.Full) {
            if (deviceKind === 1) {
                if (hasActiveNetwork) {
                    const iconIndex = Math.min(Math.floor(signalStrength * 4), 4)
                    return icon.wifiIcons[iconIndex]
                }
            } else if (deviceKind === 2) {
                return "󰀂"
            }
        } else if (connectivity === NetworkConnectivity.Limited) {
            return "󰤬"
        } else if (connectivity === NetworkConnectivity.Portal) {
            return "󰖟"
        } else if (connectivity === NetworkConnectivity.None) {
            return "󰤮"
        }
        return "󰤫"
    }

    readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]

    function signalIconFor(strength: real): string {
        const iconIndex = Math.min(Math.floor(strength * 4), 4)
        return icon.wifiIcons[iconIndex]
    }

    function formatBytes(bytes: real): string {
        if (bytes < 1024) {
            return bytes.toFixed(0) + " B"
        } else if (bytes < 1024 * 1024) {
            return (bytes / 1024).toFixed(1) + " KB"
        } else if (bytes < 1024 * 1024 * 1024) {
            return (bytes / 1024 / 1024).toFixed(1) + " MB"
        }
        return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GB"
    }

    function formatSpeed(bytesPerSec: real): string {
        if (bytesPerSec < 1024) {
            return bytesPerSec.toFixed(0) + " B/s"
        } else if (bytesPerSec < 1024 * 1024) {
            return (bytesPerSec / 1024).toFixed(1) + " KB/s"
        }
        return (bytesPerSec / 1024 / 1024).toFixed(1) + " MB/s"
    }

    readonly property string rxSpeedText: icon.formatSpeed(icon.service.rxSpeed)
    readonly property string txSpeedText: icon.formatSpeed(icon.service.txSpeed)

    readonly property bool isCaptivePortal: icon.connectivity === NetworkConnectivity.Portal
    readonly property bool isOffline: icon.connectivity === NetworkConnectivity.None
        || icon.connectivity === NetworkConnectivity.Unknown

    readonly property string statusLine: {
        if (!icon.hasDevice && icon.connectivity === NetworkConnectivity.None) {
            return "No network hardware"
        }
        if (icon.isCaptivePortal) {
            return "Sign in required (captive portal)"
        }
        if (icon.isOffline) {
            return "Offline"
        }
        if (icon.connectivity === NetworkConnectivity.Limited) {
            return "Limited connectivity"
        }
        const net = icon.service.activeNetwork
        if (net) {
            return net.name
        }
        if (icon.isWired) {
            return "Wired connected"
        }
        return "Connected"
    }

    function describe(): string {
        return "device=" + (icon.hasDevice ? "yes" : "no")
            + " connectivity=" + icon.connectivity
            + " glyph=\"" + icon.glyph + "\""
            + " status=\"" + icon.statusLine + "\""
    }
}
