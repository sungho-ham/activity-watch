#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$project_root/build/awtoday.app"
destination_app="/Applications/awtoday.app"
staged_app="/Applications/.awtoday-install-$$.app"

if /usr/bin/pgrep -f '^/Applications/awtoday.app/Contents/MacOS/awtoday-popup($| )' >/dev/null && [ "${1:-}" != "--replace-running" ]; then
    printf 'Quit awtoday before installing.\n' >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$source_app"
/usr/bin/ditto "$source_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

if [ -e "$destination_app" ]; then
    /bin/rm -rf "$destination_app"
fi
/bin/mv "$staged_app" "$destination_app"
/bin/mkdir -p "$HOME/Documents/AppData/awtoday"
printf 'Installed: %s\n' "$destination_app"
if [ "${1:-}" = "--replace-running" ]; then
    printf 'An already running app is left open. Quit and reopen it to use this version.\n'
fi
