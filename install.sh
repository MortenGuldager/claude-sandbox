#!/usr/bin/env bash
# install.sh — install claude-sandbox into PREFIX (default /opt/claude-sandbox)
# and symlink the CLI into /usr/local/bin.
#
# Re-running this script is safe; it overwrites previously-installed files.

set -euo pipefail

PREFIX="${PREFIX:-/opt/claude-sandbox}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/claude-sandbox}"
COMPLETION_DIR="${COMPLETION_DIR:-/usr/share/bash-completion/completions}"
# Short aliases get their own symlinks (both bin and completion side) so
# `csb<TAB>` works without the user having to define a shell alias — and
# bash-completion's dynamic loader can find the completion by filename.
ALIASES=(csb CSB)

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

bin_link_dir="$(dirname "$BIN_LINK")"
for alias_name in "${ALIASES[@]}"; do
    alias_link="$bin_link_dir/$alias_name"
    echo "Linking $alias_link -> $PREFIX/bin/claude-sandbox"
    ln -sfn "$PREFIX/bin/claude-sandbox" "$alias_link"
done

if [ -d "$COMPLETION_DIR" ]; then
    echo "Installing bash completion to $COMPLETION_DIR/claude-sandbox"
    install -m 0644 "$SOURCE/bash-completion/claude-sandbox" \
        "$COMPLETION_DIR/claude-sandbox"
    for alias_name in "${ALIASES[@]}"; do
        echo "Linking $COMPLETION_DIR/$alias_name -> claude-sandbox"
        ln -sfn claude-sandbox "$COMPLETION_DIR/$alias_name"
    done
else
    echo "Note: $COMPLETION_DIR not found; skipping bash completion install."
    echo "      Install the 'bash-completion' package, then re-run this script."
fi

cat <<EOF

Done.
The CLI is available as: claude-sandbox (also: ${ALIASES[*]})
Bash completion is auto-loaded on first Tab in a new shell.

Defaults work without a config file. To customize, copy the example:

    mkdir -p ~/.config/claude-sandbox
    cp $PREFIX/config.example ~/.config/claude-sandbox/config

EOF
