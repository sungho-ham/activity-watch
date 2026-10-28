#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$project_root/build/awtoday.app"
destination_app="/Applications/awtoday.app"
backup_dir="$project_root/backups/$(date +%Y%m%d-%H%M%S)-$$"
staged_app="/Applications/.awtoday-install-$$.app"

if /usr/bin/pgrep -f '^/Applications/awtoday.app/Contents/MacOS/awtoday-popup($| )' >/dev/null && [ "${1:-}" != "--replace-running" ]; then
    printf 'Quit awtoday before installing.\n' >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$source_app"
/bin/mkdir -p "$backup_dir"
/usr/bin/ditto "$source_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

if [ -e "$destination_app" ]; then
    /bin/mv "$destination_app" "$backup_dir/awtoday.app"
fi
if ! /bin/mv "$staged_app" "$destination_app"; then
    if [ -e "$backup_dir/awtoday.app" ]; then
        /bin/mv "$backup_dir/awtoday.app" "$destination_app"
    fi
    exit 1
fi
if [ -f "$project_root/build/AwTodayPopup.legacy.swift" ]; then
    /bin/cp "$project_root/build/AwTodayPopup.legacy.swift" "$backup_dir/AwTodayPopup.legacy.swift"
fi
/bin/mkdir -p "$HOME/Documents/AppData/awtoday"
printf 'Installed: %s\nPrevious app/source backup: %s\n' "$destination_app" "$backup_dir"
if [ "${1:-}" = "--replace-running" ]; then
    printf 'An already running app is left open. Quit and reopen it to use this version.\n'
fi
