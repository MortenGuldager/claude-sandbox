#!/usr/bin/env bash
# install.sh — install claude-sandbox into PREFIX (default /opt/claude-sandbox)
# and symlink the CLI into /usr/local/bin.
#
# Re-running this script is safe; it overwrites previously-installed files.

set -euo pipefail

PREFIX="${PREFIX:-/opt/claude-sandbox}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-sandbox}"
COMPLETION_DIR="${COMPLETION_DIR:-/usr/share/bash-completion/completions}"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "install.sh must be run as root (try: sudo $0)" >&2
    exit 1
fi

SOURCE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

echo "Installing claude-sandbox to $PREFIX"
install -d "$PREFIX/bin"

install -m 0755 "$SOURCE/bin/claude-sandbox" \
    "$PREFIX/bin/claude-sandbox"
install -m 0644 "$SOURCE/config.example" "$PREFIX/config.example"
install -m 0644 "$SOURCE/README.md"      "$PREFIX/README.md"
install -m 0644 "$SOURCE/LICENSE"        "$PREFIX/LICENSE"

echo "Linking $BIN_LINK -> $PREFIX/bin/claude-sandbox"
ln -sfn "$PREFIX/bin/claude-sandbox" "$BIN_LINK"

if [ -d "$COMPLETION_DIR" ]; then
    echo "Installing bash completion to $COMPLETION_DIR/claude-sandbox"
    install -m 0644 "$SOURCE/bash-completion/claude-sandbox" \
        "$COMPLETION_DIR/claude-sandbox"
else
    echo "Note: $COMPLETION_DIR not found; skipping bash completion install."
    echo "      Install the 'bash-completion' package, then re-run this script."
fi

cat <<EOF

Done.
The CLI is available as: claude-sandbox
Bash completion is auto-loaded on first Tab in a new shell.

Defaults work without a config file. To customize, copy the example:

    mkdir -p ~/.config/claude-sandbox
    cp $PREFIX/config.example ~/.config/claude-sandbox/config

EOF
