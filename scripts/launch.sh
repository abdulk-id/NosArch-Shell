#!/usr/bin/env bash
#
# launch.sh — run the nosarch-shell straight from this repository checkout.
#
# Nothing is installed and no autostart entry is required: this points quickshell
# at the repo's shell.qml by explicit path, which is exactly what the shell is
# designed to run from during development. It runs alongside the live desktop
# (waybar, swaync, ...); the maintainer chooses the cutover.
#
#   ./scripts/launch.sh          # run the shell
#   ./scripts/launch.sh -n       # exit if an instance of this config already runs
#   ./scripts/launch.sh -vv      # any extra args are passed straight to quickshell
#
# quickshell reloads automatically when a watched QML file changes on save (the
# config directory is watched). Saving a file re-evaluates the config in the same
# process, and the log states plainly whether it started fresh or reloaded.
#
set -euo pipefail

# Resolve the repository root (the directory that holds shell.qml), no matter
# where the script is invoked from.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG="$ROOT/shell.qml"

if [[ ! -f "$CONFIG" ]]; then
    echo "launch: cannot find the shell entrypoint at $CONFIG" >&2
    exit 1
fi

if ! command -v quickshell >/dev/null 2>&1; then
    echo "launch: quickshell is not on PATH (Quickshell must be installed to run the shell)" >&2
    exit 1
fi

echo "launch: quickshell -p $CONFIG $*"
exec quickshell -p "$CONFIG" "$@"
