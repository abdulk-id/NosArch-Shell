//@ pragma UseQApplication

import Quickshell

import "shell"
import "shell/notifications"
import "shell/osds"
import "shell/topisland"

ShellRoot {
    id: shell

    Wallpaper {}

    TopIsland {}

    ProgressOSDPanel {}
    MediaOsd {}
    NotificationPopup {}
}
