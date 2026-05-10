#!/usr/bin/env bash
# uninstall.sh — remove claude-sandbox files installed by install.sh.
# User configuration under ~/.config/claude-sandbox is left in place.

set -euo pipefail

PREFIX="${PREFIX:-/opt/claude-sandbox}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-sandbox}"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "uninstall.sh must be run as root (try: sudo $0)" >&2
    exit 1
fi

echo "Removing $BIN_LINK"
rm -f "$BIN_LINK"

echo "Removing $PREFIX"
rm -rf "$PREFIX"

echo
echo "Done. User config under ~/.config/claude-sandbox was left untouched."
echo "Existing sandbox containers were not deleted; remove them with:"
echo "    incus list   # find them"
echo "    incus delete -f <name>"
