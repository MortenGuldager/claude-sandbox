#!/usr/bin/env bash
# install.sh — install claude-sandbox into PREFIX (default /opt/claude-sandbox)
# and symlink the CLI into /usr/local/bin.
#
# Re-running this script is safe; it overwrites previously-installed files.

set -euo pipefail

PREFIX="${PREFIX:-/opt/claude-sandbox}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-sandbox}"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "install.sh must be run as root (try: sudo $0)" >&2
    exit 1
fi

SOURCE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

echo "Installing claude-sandbox to $PREFIX"
install -d "$PREFIX/bin" "$PREFIX/container"

install -m 0755 "$SOURCE/bin/claude-sandbox" \
    "$PREFIX/bin/claude-sandbox"
install -m 0755 "$SOURCE/container/claude-status-reporter.sh" \
    "$PREFIX/container/claude-status-reporter.sh"
install -m 0644 "$SOURCE/container/claude-status-reporter.service" \
    "$PREFIX/container/claude-status-reporter.service"
install -m 0644 "$SOURCE/config.example" "$PREFIX/config.example"
install -m 0644 "$SOURCE/README.md"      "$PREFIX/README.md"
install -m 0644 "$SOURCE/LICENSE"        "$PREFIX/LICENSE"

echo "Linking $BIN_LINK -> $PREFIX/bin/claude-sandbox"
ln -sfn "$PREFIX/bin/claude-sandbox" "$BIN_LINK"

cat <<EOF

Done.
The CLI is available as: claude-sandbox

Defaults work without a config file. To customize, copy the example:

    mkdir -p ~/.config/claude-sandbox
    cp $PREFIX/config.example ~/.config/claude-sandbox/config

EOF
