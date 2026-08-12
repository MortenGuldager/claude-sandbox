# tests/lib.sh — harness for the claude-sandbox test suite.
#
# `bin/claude-sandbox` cannot simply be sourced: its top level resolves
# the cwd, hashes it into a container name, and may reach the network to
# resolve the reporter SHA. So instead of loading the script we lift out
# the single functions under test with `load_fn`, then run them against
# stubbed `incus` and stubbed file writers.
#
# That keeps the whole suite runnable anywhere — including inside a
# sandbox, where there is no incus daemon to talk to. What it cannot
# cover is the container lifecycle itself; see tests/README.md.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
# Overridable so a mutated copy can be run against the suite, which is
# how the suite itself is checked for teeth.
SCRIPT="${SCRIPT:-$REPO_ROOT/bin/claude-sandbox}"
GOLDEN_DIR="$TESTS_DIR/golden"

WORK_DIR=""
FAILURES=0
CHECKS=0
UPDATE_GOLDEN="${UPDATE_GOLDEN:-0}"

# --- function loading -------------------------------------------------------

# Extracts one function definition from the script by name and evals it.
# Relies on the file's consistent layout: a definition starts at column 1
# as `name() {` and ends at a line that is exactly `}`. Doc writers end
# on `} | write_sandbox_user_file ...`, which is not a bare `}`, so the
# terminator is unambiguous.
load_fn() {
    local fn="$1" body
    body="$(awk -v fn="$fn" '
        index($0, fn "() {") == 1 { found = 1 }
        found                     { print }
        found && $0 == "}"        { exit }
    ' "$SCRIPT")"
    if [ -z "$body" ]; then
        echo "harness error: function '$fn' not found in $SCRIPT" >&2
        exit 2
    fi
    eval "$body"
}

# --- stubs ------------------------------------------------------------------

# Captured `incus` invocations, one per line, for tests that assert a
# side effect was requested rather than inspecting its result.
INCUS_LOG=""

# Stub for the real `incus`. Two behaviours:
#   * `incus exec ... bash -c <prog> _ <args>` actually runs <prog> under
#     $STUB_HOME, so the in-container jq merges are exercised for real.
#   * everything else is recorded and succeeds.
# The container-side `sudo -u ubuntu -H` would reset HOME; the stub sets
# HOME to a scratch dir instead, which is what makes the merge testable.
incus() {
    local -a a=("$@")
    local i
    INCUS_LOG+="incus $* "$'\n'
    for ((i = 0; i < ${#a[@]}; i++)); do
        if [ "${a[i]}" = "bash" ] && [ "${a[i + 1]}" = "-c" ]; then
            HOME="$STUB_HOME" bash -c "${a[i + 2]}" "${a[@]:i + 3}"
            return $?
        fi
    done
    return 0
}

# Stub for the container file writer: keeps the content on the host so a
# test can diff it, keyed by basename (every doc has a unique filename).
write_sandbox_user_file() {
    local path="$1"
    mkdir -p "$CAPTURE_DIR"
    cat > "$CAPTURE_DIR/$(basename "$path")"
}

# --- deterministic environment ---------------------------------------------

# Fixed stand-ins for everything the generated docs interpolate, so golden
# files stay stable across machines and users.
setup_env() {
    WORK_DIR="$(mktemp -d)"
    STUB_HOME="$WORK_DIR/home"
    CAPTURE_DIR="$WORK_DIR/captured"
    CONFIG_DIR="$WORK_DIR/config"
    mkdir -p "$STUB_HOME/.claude" "$CAPTURE_DIR" "$CONFIG_DIR"

    # Assets are read from the checkout, which is also what a golden
    # comparison should be pinning: the files as they ship.
    ASSET_DIR="$REPO_ROOT/share"

    REPO_DIR="/test/project"
    CONTAINER_NAME="csb-project-abc123"
    SANDBOX_CLAUDE_MD="/home/ubuntu/.claude/CLAUDE.md"
    SANDBOX_CLAUDE_D="/home/ubuntu/.claude/CLAUDE.d"
    RESOLVED_GIT_NAME="Test User"
    RESOLVED_GIT_EMAIL="test@example.com"
    SANDBOX_OUTPUT_STYLE="STE100"

    export INCUS_LOG=""
}

teardown_env() {
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    WORK_DIR=""
}

# --- assertions -------------------------------------------------------------

pass() { CHECKS=$((CHECKS + 1)); printf '  ok    %s\n' "$1"; }
fail() {
    CHECKS=$((CHECKS + 1))
    FAILURES=$((FAILURES + 1))
    printf '  FAIL  %s\n' "$1"
    [ -n "${2-}" ] && printf '        %s\n' "$2"
    return 0
}

section() { printf '\n%s\n' "$1"; }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label" "expected [$expected], got [$actual]"
    fi
}

assert_true() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "command failed: $*"; fi
}

assert_false() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "$label" "command unexpectedly succeeded: $*"; else pass "$label"; fi
}

assert_contains() {
    local label="$1" needle="$2" file="$3"
    if grep -qF -- "$needle" "$file"; then
        pass "$label"
    else
        fail "$label" "'$needle' not found in $file"
    fi
}

# Compares a produced file against tests/golden/<name>. With
# UPDATE_GOLDEN=1 the golden file is rewritten instead of compared, which
# is how a deliberate content change is recorded.
assert_golden() {
    local label="$1" actual="$2" name="$3"
    local golden="$GOLDEN_DIR/$name"

    if [ "$UPDATE_GOLDEN" = "1" ]; then
        mkdir -p "$GOLDEN_DIR"
        cp "$actual" "$golden"
        pass "$label (golden updated)"
        return 0
    fi

    if [ ! -f "$golden" ]; then
        fail "$label" "no golden file at $golden; run with UPDATE_GOLDEN=1 to create it"
        return 0
    fi

    if diff -u "$golden" "$actual" > "$WORK_DIR/diff.out" 2>&1; then
        pass "$label"
    else
        fail "$label" "differs from $name:"
        sed 's/^/        /' "$WORK_DIR/diff.out" >&2
    fi
}
