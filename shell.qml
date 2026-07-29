//@ pragma UseQApplication

import Quickshell

import "shell"
import "shell/topisland"
import "shell/osds"
import "shell/notifications"

ShellRoot {
    id: shell

    Wallpaper {}

    TopIsland {}

    ProgressOSDPanel {}
    MediaOsd {}
    NotificationPopup {}
}
