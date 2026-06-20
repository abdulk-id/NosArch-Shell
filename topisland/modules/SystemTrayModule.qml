import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import "../../ui" as UI

Item {
    id: systemTrayModule

    // UI ===
    implicitWidth: systemTrayRow.implicitWidth

    Row {
        id: systemTrayRow
        spacing: 20
        anchors.centerIn: parent

        Repeater {
            model: SystemTray.items

            Item {
                id: trayItem
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                property bool hovered: false
                property bool menuShowing: false

                QsMenuOpener {
                    id: menuOpener
                    menu: modelData.menu
                }

                PanelWindow {
                    // Menu PanelWindow
                    id: menuWindow
                    visible: trayItem.menuShowing

                    anchors {
                        top: true
                        right: true
                    }
                    margins {
                        top: 40
                        right: 40
                        // TODO: Hardcoded to be 40px away from right screen edge, not automatically showing centered under the icon
                    }

                    color: "transparent"

                    implicitWidth: menuCol.implicitWidth + 16
                    implicitHeight: menuCol.implicitHeight + 16
                    exclusiveZone: -1
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: UI.Colors.background
                        border.color: UI.Colors.foregroundMuted
                        border.width: 1
                        clip: true

                        opacity: trayItem.menuShowing ? 1 : 0
                        scale: trayItem.menuShowing ? 1 : 0.95
                        transformOrigin: Item.Bottom

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Click outside to close
                        // TODO: Doesn't work
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: trayItem.menuShowing = false
                        }

                        Column {
                            id: menuCol

                            anchors.centerIn: parent
                            spacing: 1

                            Repeater {
                                model: menuOpener.children.values

                                delegate: Item {
                                    width: menuLabel.implicitWidth + 20
                                    height: modelData.isSeparator ? 10 : 30

                                    Rectangle {
                                        // Menu separaters
                                        anchors.centerIn: parent
                                        width: parent.width
                                        height: 1

                                        color: UI.Colors.foregroundMuted

                                        opacity: 0.5
                                        visible: modelData.isSeparator
                                    }

                                    Rectangle {
                                        // Menu items
                                        anchors.fill: parent
                                        radius: 6

                                        color: entryMa.containsMouse ? Qt.alpha(UI.Colors.accent, 0.15) : "transparent"
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 100
                                            }
                                        }

                                        Text {
                                            id: menuLabel
                                            text: modelData.text || ""

                                            anchors.centerIn: parent

                                            color: modelData.enabled ? (UI.Colors.foreground) : (UI.Colors.foregroundMuted)
                                            font.pixelSize: UI.Fonts.fontSizeSmall
                                            font.family: UI.Fonts.fontFamily
                                        }

                                        MouseArea {
                                            id: entryMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (modelData.enabled) {
                                                    modelData.triggered();
                                                    trayItem.menuShowing = false;
                                                }
                                            }
                                        }

                                        visible: !modelData.isSeparator
                                    }
                                }
                            }
                        }
                    }
                }

                IconImage {
                    id: icon

                    anchors.centerIn: parent
                    width: UI.Fonts.fontSize
                    height: UI.Fonts.fontSize
                    implicitSize: UI.Fonts.fontSize

                    source: systemTrayModule._iconProviderSource(modelData.icon)
                    asynchronous: true
                    mipmap: true

                    visible: glyphIcon.text === ""
                    opacity: 1.0
                }

                IconImage {
                    anchors.centerIn: parent
                    width: UI.Fonts.fontSize
                    height: UI.Fonts.fontSize
                    implicitSize: UI.Fonts.fontSize

                    source: systemTrayModule._isDirectIconSource(modelData.icon) ? "" : (modelData.icon || "")
                    asynchronous: true
                    mipmap: true

                    visible: glyphIcon.text === "" && source !== "" && icon.status === Image.Error
                    opacity: icon.opacity
                }

                Text {
                    id: glyphIcon
                    anchors.centerIn: parent

                    text: systemTrayModule._customGlyph(modelData)

                    color: trayItem.hovered ? (UI.Colors.accent) : (UI.Colors.foreground)
                    font: {
                        pixelSize: UI.Fonts.fontSizeSmall;
                        family: UI.Fonts.fontFamily;
                    }
                    renderType: Text.NativeRendering

                    opacity: 1.0
                    visible: text !== ""

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                Rectangle {
                    // Tooltip of app icon shown on mouse hovering on icon.
                    anchors.top: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    z: 99
                    // TODO: Doesn't render when outside bar area (should be visible as an overlay)

                    width: tooltipText.implicitWidth + 20
                    height: 25
                    radius: 5

                    color: UI.Colors.background
                    border.color: UI.Colors.foregroundMuted
                    border.width: 1

                    visible: trayItem.hovered && !trayItem.menuShowing
                    opacity: trayItem.hovered && !trayItem.menuShowing ? 1 : 0

                    Text {
                        id: tooltipText
                        anchors.centerIn: parent

                        text: modelData.tooltipTitle !== "" ? modelData.tooltipTitle : modelData.title

                        color: UI.Colors.foreground
                        font: {
                            family: UI.Fonts.fontFamily;
                            pixelSize: UI.Fonts.fontSizeSmall;
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    onEntered: trayItem.hovered = true
                    onExited: trayItem.hovered = false

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            modelData.activate();
                        } else if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu) {
                                trayItem.menuShowing = !trayItem.menuShowing;
                            }
                        }
                    }
                }
            }
        }
    }
    // ===

    // Behaviour ===
    function _isDirectIconSource(icon) {
        const value = icon || "";
        return value.startsWith("/") || value.startsWith("file:") || value.startsWith("image:") || value.startsWith("qrc:") || value.startsWith("data:");
    }

    function _iconProviderSource(icon) {
        const value = icon || "";
        if (value === "")
            return "";
        if (_isDirectIconSource(value))
            return value;
        return "image://icon/" + encodeURIComponent(value);
    }

    function _traySearchText(item) {
        return [item?.id || "", item?.title || "", item?.tooltipTitle || "", item?.tooltipDescription || "", item?.icon || ""].join(" ").toLowerCase();
    }

    function _hasAny(text, values) {
        for (const value of values) {
            if (text.includes(value))
                return true;
        }
        return false;
    }

    function _customGlyph(item) {
        const text = _traySearchText(item);
        if (_hasAny(text, ["spotify"]))
            return "";
        if (_hasAny(text, ["discord", "vesktop"]))
            return "";
        if (_hasAny(text, ["telegram"]))
            return "";
        if (_hasAny(text, ["steam"]))
            return "";
        if (_hasAny(text, ["slack"]))
            return "󰒱";
        if (_hasAny(text, ["obs", "obsidian"]))
            return text.includes("obsidian") ? "󰎚" : "󰐾";
        if (_hasAny(text, ["dropbox"]))
            return "󰇣";
        if (_hasAny(text, ["github", "gitkraken"]))
            return "󰊤";
        if (_hasAny(text, ["signal"]))
            return "󰭹";
        if (_hasAny(text, ["whatsapp"]))
            return "󰖣";
        if (_hasAny(text, ["element", "matrix"]))
            return "󱘖";
        if (_hasAny(text, ["teams"]))
            return "󰊻";
        if (_hasAny(text, ["zoom"]))
            return "󰬡";
        if (_hasAny(text, ["chromium", "chrome", "brave", "firefox", "browser"]))
            return "󰖟";
        if (_hasAny(text, ["code", "vscode", "cursor", "zed"]))
            return "󰨞";
        if (_hasAny(text, ["thunderbird", "mail"]))
            return "󰇮";
        if (_hasAny(text, ["syncthing"]))
            return "󱂵";
        if (_hasAny(text, ["nextcloud"]))
            return "󰅟";
        if (_hasAny(text, ["tailscale"]))
            return "󰛳";
        if (_hasAny(text, ["vpn", "proton"]))
            return "󰦝";
        if (_hasAny(text, ["docker"]))
            return "󰡨";
        if (_hasAny(text, ["qbittorrent", "torrent", "transmission"]))
            return "󰃘";
        if (_hasAny(text, ["mpv", "vlc", "media player"]))
            return "󰐊";
        if (_hasAny(text, ["bluetooth", "blueberry", "blueman"]))
            return "󰂯";
        if (_hasAny(text, ["network", "wifi", "nm-applet"]))
            return "󰖩";
        if (_hasAny(text, ["volume", "audio", "pipewire", "pavucontrol"]))
            return "󰕾";
        if (_hasAny(text, ["battery", "power"]))
            return "󰁹";
        if (_hasAny(text, ["clipboard"]))
            return "󰅌";
        if (_hasAny(text, ["calendar"]))
            return "󰃭";
        if (_hasAny(text, ["notes", "note"]))
            return "󱞎";
        if (_hasAny(text, ["input method", "input-keyboard"]))
            return "󰧹";
        return "";
    }
    // ===
}
