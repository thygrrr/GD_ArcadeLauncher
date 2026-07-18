#!/bin/sh
printf '\033c\033]0;%s\a' c-base Arcade Launcher
base_path="$(dirname "$(realpath "$0")")"
"$base_path/launcher.x86_64" "$@"
