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

# --- Incus prerequisites ----------------------------------------------------
# csb is a thin wrapper over `incus`, so a fresh host needs three things
# in place before csb is useful: the incus package itself, an initialized
# default storage pool/network, and the invoking user added to the
# incus-admin group. We handle each idempotently so re-running install.sh
# on an already-configured host is a no-op.

ADDED_TO_GROUP=""

if ! command -v incus >/dev/null 2>&1; then
    echo "Incus not found; installing via apt..."
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "  apt-get is unavailable; install incus manually and re-run." >&2
        exit 1
    fi
    apt-get update
    apt-get install -y incus
fi

# An initialized incus has at least one storage pool. Empty output means
# we have never run `incus admin init` (or any equivalent) on this host.
if ! incus storage list --format csv 2>/dev/null | grep -q .; then
    echo "Initializing incus (incus admin init --minimal)..."
    incus admin init --minimal
fi

# Add the invoking user to incus-admin so they can talk to the daemon
# without sudo. SUDO_USER is empty when install.sh is run as a real root
# login, in which case we can't guess who the operator is.
target_user="${SUDO_USER:-}"
if [ -n "$target_user" ]; then
    if ! id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx incus-admin; then
        echo "Adding $target_user to incus-admin group..."
        usermod -aG incus-admin "$target_user"
        ADDED_TO_GROUP="$target_user"
    fi
else
    echo "Note: not invoked via sudo; skipping incus-admin group add."
    echo "      Add yourself manually:  sudo usermod -aG incus-admin <you>"
fi

# --- claude-sandbox files ---------------------------------------------------

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

if [ -n "$ADDED_TO_GROUP" ]; then
    cat <<EOF
Note: $ADDED_TO_GROUP was just added to the incus-admin group. The new
membership won't apply to existing shells — log out and back in, or run
'newgrp incus-admin' in a new shell, before using csb.

EOF
fi
