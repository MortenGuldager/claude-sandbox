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

# csb needs a couple of host-side tools beyond incus: curl fetches the
# reporter commit from the GitHub API and jq parses the SHA out of it. A
# fresh Raspberry Pi OS ships neither, and a missing jq surfaces at
# `create` time as a misleading "check network" error (the failed jq is
# swallowed), so make sure both are present up front.
host_deps=()
for t in curl jq; do command -v "$t" >/dev/null 2>&1 || host_deps+=("$t"); done
if [ "${#host_deps[@]}" -gt 0 ]; then
    echo "Installing host prerequisites: ${host_deps[*]}"
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "  apt-get is unavailable; install ${host_deps[*]} manually and re-run." >&2
        exit 1
    fi
    apt-get update
    apt-get install -y "${host_deps[@]}"
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

# --- Kernel cgroup memory controller (Raspberry Pi) -------------------------
# csb caps each sandbox's RAM and swap, which needs the cgroup v2 memory
# controller. A normal PC has it on already; the default Raspberry Pi OS
# kernel ships it off, so there we offer to enable it by editing the boot
# cmdline. The whole block is skipped when the controller is already
# active, so it never touches a normal host.
if ! grep -qw memory /sys/fs/cgroup/cgroup.controllers 2>/dev/null; then
    cmdline=""
    for c in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
        [ -f "$c" ] && { cmdline="$c"; break; }
    done
    if [ -z "$cmdline" ]; then
        echo "Note: the cgroup memory controller is disabled and no Raspberry Pi"
        echo "      cmdline.txt was found. Enable it for your platform if you want"
        echo "      per-sandbox memory/swap limits to take effect."
    elif grep -q 'cgroup_enable=memory' "$cmdline"; then
        echo "Note: $cmdline already enables the memory cgroup; reboot to activate it."
    else
        echo
        echo "The kernel's cgroup memory controller is disabled, so claude-sandbox"
        echo "cannot enforce per-sandbox RAM/swap limits. On a Raspberry Pi this is"
        echo "fixed by adding 'cgroup_enable=memory cgroup_memory=1' to"
        echo "    $cmdline"
        echo "which is a boot file; the change needs a reboot to take effect."
        do_edit=""
        if [ -t 0 ]; then
            printf "Append it now? [y/N] "
            read -r reply || reply=""
            case "$reply" in [yY]|[yY][eE][sS]) do_edit=1 ;; esac
        else
            echo "Non-interactive run; leaving $cmdline unchanged."
        fi
        if [ -n "$do_edit" ]; then
            # cmdline.txt is a single space-separated line; append in place,
            # preserving that single-line format, and keep a backup.
            cp -a "$cmdline" "$cmdline.bak"
            printf '%s cgroup_enable=memory cgroup_memory=1\n' \
                "$(tr -d '\n' < "$cmdline")" > "$cmdline"
            echo "Updated $cmdline (backup at $cmdline.bak). Reboot to apply."
        else
            echo "Left $cmdline unchanged. Add the options above and reboot when ready."
        fi
    fi
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
