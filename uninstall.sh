#!/usr/bin/env bash
# uninstall.sh — remove claude-sandbox files installed by install.sh.
# User configuration under ~/.config/claude-sandbox is left in place.

set -euo pipefail

PREFIX="${PREFIX:-/opt/claude-sandbox}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-sandbox}"
COMPLETION_DIR="${COMPLETION_DIR:-/usr/share/bash-completion/completions}"
ALIASES=(csb CSB)

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "uninstall.sh must be run as root (try: sudo $0)" >&2
    exit 1
fi

echo "Removing $BIN_LINK"
rm -f "$BIN_LINK"

bin_link_dir="$(dirname "$BIN_LINK")"
for alias_name in "${ALIASES[@]}"; do
    alias_link="$bin_link_dir/$alias_name"
    echo "Removing $alias_link"
    rm -f "$alias_link"
done

echo "Removing $COMPLETION_DIR/claude-sandbox"
rm -f "$COMPLETION_DIR/claude-sandbox"
for alias_name in "${ALIASES[@]}"; do
    echo "Removing $COMPLETION_DIR/$alias_name"
    rm -f "$COMPLETION_DIR/$alias_name"
done

echo "Removing $PREFIX"
rm -rf "$PREFIX"

echo
echo "Done. User config under ~/.config/claude-sandbox was left untouched."
echo "Existing sandbox containers were not deleted; remove them with:"
echo "    incus list   # find them"
echo "    incus delete -f <name>"
