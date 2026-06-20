import Quickshell

import "topisland"

ShellRoot {
    id: shell

    readonly property var theme: ({
            // Colors
            accent: "#3584E4",
            background: "#1A1A1A",
            foreground: "#FFFFFF",
            foregroundMuted: "#444B6A",
            // Fonts
            fontFamily: "JetbrainsMono Nerd Font",
            fontSize: 14,
            fontSizeSmall: 13,
            fontSizeIcons: 18
        })

    TopIsland {}
}
