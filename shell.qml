import Quickshell

import "shell/topisland"
import "shell/osds"

ShellRoot {
    id: shell

    // Top Island
    TopIsland {}

    // OSD
    VolumeOsd {}
    MediaOsd {}
}
