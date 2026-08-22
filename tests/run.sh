#!/usr/bin/env bash
# tests/run.sh — characterisation tests for claude-sandbox.
#
# Written to guard a refactor: the embedded payloads (output style, hook
# script, seeded skill, CLAUDE.d docs) are pinned byte-for-byte against
# tests/golden/, so moving them out of the script must not change what
# lands in a sandbox. Behavioural checks cover the parts a refactor is
# most likely to break silently: frontmatter validity, style-name
# lookup, the settings.json merge, and install.sh completeness.
#
# Usage:
#   tests/run.sh                 run everything
#   UPDATE_GOLDEN=1 tests/run.sh rewrite golden files after an
#                                intentional content change
#
# Deliberately no `set -e`: every assertion runs so one failure does not
# hide the rest.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- 1. scripts parse -------------------------------------------------------

section "shell syntax"
for f in bin/claude-sandbox install.sh uninstall.sh; do
    assert_true "$f parses" bash -n "$REPO_ROOT/$f"
done

# --- 2. output style: content and schema ------------------------------------

section "output style"
setup_env
load_fn render_asset
load_fn sed_escape
load_fn render_asset_to
load_fn project_slug_for_path
load_fn seed_output_styles
load_fn output_style_exists

styles="$WORK_DIR/output-styles"
seed_output_styles "$styles"
style_file="$styles/ste100.md"

assert_true "seeds ste100.md" test -f "$style_file"
assert_golden "ste100.md matches golden" "$style_file" "ste100.md"

# The GIST variant is seeded alongside, so `/output-style` can switch to
# it in any sandbox. Same strict-schema and coding-instruction invariants
# apply.
gist_file="$styles/gist.md"
assert_true "seeds gist.md" test -f "$gist_file"
assert_golden "gist.md matches golden" "$gist_file" "gist.md"
gist_keys="$(awk 'NR==1 && $0=="---" {inside=1; next}
                  inside && $0=="---" {exit}
                  inside && /^[a-zA-Z-]+:/ {sub(/:.*/, ""); print}' "$gist_file" | sort | tr '\n' ' ')"
assert_eq "variant frontmatter keys are exactly the supported ones" \
    "description keep-coding-instructions name " "$gist_keys"
assert_eq "variant declares name GIST" "GIST" \
    "$(sed -n 's/^name:[[:space:]]*//p' "$gist_file" | head -n1)"
assert_contains "variant keeps default coding instructions" \
    "keep-coding-instructions: true" "$gist_file"

# Claude Code parses output-style frontmatter with a *strict* schema:
# an unknown key makes it drop the style silently, so the accepted keys
# are an invariant worth pinning. force-for-plugin is accepted by the
# schema but only meaningful for plugin styles, and warned about for user
# styles, so it must stay absent.
keys="$(awk 'NR==1 && $0=="---" {inside=1; next}
             inside && $0=="---" {exit}
             inside && /^[a-zA-Z-]+:/ {sub(/:.*/, ""); print}' "$style_file" | sort | tr '\n' ' ')"
assert_eq "frontmatter keys are exactly the supported ones" \
    "description keep-coding-instructions name " "$keys"

name_field="$(sed -n 's/^name:[[:space:]]*//p' "$style_file" | head -n1)"
assert_eq "style declares name STE100" "STE100" "$name_field"
assert_contains "keeps default coding instructions" \
    "keep-coding-instructions: true" "$style_file"

# The default in the script names the style by its `name:` field. If the
# two drift apart, every `create` warns and no style is applied.
default_style="$(sed -n 's/^SANDBOX_OUTPUT_STYLE="\(.*\)"$/\1/p' "$SCRIPT" | head -n1)"
assert_eq "SANDBOX_OUTPUT_STYLE default matches the seeded style name" \
    "$name_field" "$default_style"

# Re-seeding must be a no-op in content: `create` runs it every time.
cp "$style_file" "$WORK_DIR/first.md"
seed_output_styles "$styles"
assert_true "re-seeding is idempotent" cmp -s "$WORK_DIR/first.md" "$style_file"

# --- 3. output style: name lookup -------------------------------------------

section "output_style_exists"
lookup="$WORK_DIR/lookup"
mkdir -p "$lookup" "$WORK_DIR/empty"
seed_output_styles "$lookup"
printf -- '---\nname: "Quoted Name"\ndescription: x\n---\nbody\n' > "$lookup/quoted.md"
printf -- '---\nname: aXc\ndescription: x\n---\nbody\n' > "$lookup/regexy.md"
printf -- '---\ndescription: x\n---\nbody\n' > "$lookup/nameless.md"

assert_true  "finds style by frontmatter name"      output_style_exists "$lookup" "STE100"
assert_true  "finds style by filename"              output_style_exists "$lookup" "ste100"
assert_true  "finds quoted frontmatter name"        output_style_exists "$lookup" "Quoted Name"
assert_true  "finds style whose only id is a file"  output_style_exists "$lookup" "nameless"
assert_false "rejects unknown name"                 output_style_exists "$lookup" "Nope"
assert_false "rejects empty directory"              output_style_exists "$WORK_DIR/empty" "STE100"
assert_false "rejects missing directory"            output_style_exists "$WORK_DIR/absent" "STE100"
# A name is data, not a pattern: "a.c" must not match a style called aXc.
assert_false "treats the queried name literally"    output_style_exists "$lookup" "a.c"

# --- 4. settings.json merge -------------------------------------------------

section "activate_output_style"
load_fn activate_output_style

CONFIG_DIR="$WORK_DIR/cfg"
mkdir -p "$CONFIG_DIR/output-styles"
seed_output_styles "$CONFIG_DIR/output-styles"
settings="$STUB_HOME/.claude/settings.json"
seed_settings() { printf '{"theme":"dark","skipDangerousModePermissionPrompt":true}\n' > "$settings"; }

seed_settings
SANDBOX_OUTPUT_STYLE="STE100" activate_output_style
assert_eq "selects the configured style" "STE100" "$(jq -r '.outputStyle' "$settings")"
assert_eq "keeps unrelated settings"     "dark"   "$(jq -r '.theme' "$settings")"

SANDBOX_OUTPUT_STYLE="" activate_output_style
assert_eq "blank config removes the key" "null" "$(jq -r '.outputStyle // "null"' "$settings")"
assert_eq "still keeps unrelated settings" "true" \
    "$(jq -r '.skipDangerousModePermissionPrompt' "$settings")"

# An unknown name must not be written: Claude Code would fall back to the
# default style without a word, which is the failure we want loud.
seed_settings
warning="$(SANDBOX_OUTPUT_STYLE="Nope" activate_output_style 2>&1 >/dev/null)"
assert_eq "unknown style leaves settings untouched" "null" \
    "$(jq -r '.outputStyle // "null"' "$settings")"
case "$warning" in
    *"no output style named 'Nope'"*) pass "unknown style warns on stderr" ;;
    *) fail "unknown style warns on stderr" "got: $warning" ;;
esac

# Missing settings.json is the normal case on a fresh container.
rm -f "$settings"
SANDBOX_OUTPUT_STYLE="STE100" activate_output_style
assert_eq "creates settings.json when absent" "STE100" "$(jq -r '.outputStyle' "$settings")"

CONFIG_DIR="/test/config"

# --- 5. hooks ---------------------------------------------------------------

section "managed hooks"
load_fn seed_claude_hooks
seed_claude_hooks
hook="$CAPTURE_DIR/inject-global-memory.sh"
cq="$CAPTURE_DIR/closed-question.sh"

assert_true "writes the hook script" test -f "$hook"
assert_golden "hook matches golden" "$hook" "inject-global-memory.sh"
assert_true "hook parses" bash -n "$hook"
assert_true "writes the closed-question hook" test -f "$cq"
assert_golden "closed-question hook matches golden" "$cq" "closed-question.sh"
assert_true "closed-question hook parses" bash -n "$cq"
case "$INCUS_LOG" in
    *"chmod 0755"*) pass "hook is made executable" ;;
    *) fail "hook is made executable" "no chmod in incus log" ;;
esac
case "$INCUS_LOG" in
    *'.hooks.SessionStart'*) pass "hook is registered in settings.json" ;;
    *) fail "hook is registered in settings.json" "no jq settings merge in incus log" ;;
esac
case "$INCUS_LOG" in
    *'.hooks.UserPromptSubmit'*) pass "closed-question hook is registered" ;;
    *) fail "closed-question hook is registered" "no UserPromptSubmit in incus log" ;;
esac

# Behaviour: with an index present the hook must emit the documented
# additionalContext JSON, since plain stdout is not added to context.
mkdir -p "$STUB_HOME/.claude/global-memory"
printf -- '- [A fact](a.md) — hook line\n' > "$STUB_HOME/.claude/global-memory/MEMORY.md"
chmod +x "$hook"
out="$(HOME="$STUB_HOME" "$hook" 2>/dev/null)"
assert_eq "hook emits SessionStart event" "SessionStart" \
    "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("hook line")' >/dev/null; then
    pass "hook injects the index content"
else
    fail "hook injects the index content" "additionalContext missing the index"
fi

: > "$STUB_HOME/.claude/global-memory/MEMORY.md"
out="$(HOME="$STUB_HOME" "$hook" 2>/dev/null)"
assert_eq "empty index emits nothing" "" "$out"

# Behaviour: the closed-question hook must fire on a short yes/no question
# and stay silent otherwise. It reads the prompt as JSON on stdin.
chmod +x "$cq"
cq_ctx() {
    jq -nc --arg p "$1" '{prompt:$p}' | "$cq" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""'
}
assert_contains_str() {
    case "$2" in
        *"$3"*) pass "$1" ;;
        *) fail "$1" "missing '$3' in: $2" ;;
    esac
}

out="$(cq_ctx 'er det en god ide?')"
assert_contains_str "fires on a Danish yes/no question" "$out" "first word is the answer"
assert_eq "emits UserPromptSubmit event" "UserPromptSubmit" \
    "$(jq -nc --arg p 'kan vi det?' '{prompt:$p}' | "$cq" 2>/dev/null \
        | jq -r '.hookSpecificOutput.hookEventName')"
assert_eq "fires on an English yes/no question" "0" \
    "$([ -n "$(cq_ctx 'should we merge this?')" ] && echo 0 || echo 1)"
assert_eq "ignores a question with no yes/no opener" "" \
    "$(cq_ctx 'hvorfor virker det ikke?')"
assert_eq "ignores a statement" "" "$(cq_ctx 'kan vi lige rette det')"
assert_eq "ignores an empty prompt" "" "$(cq_ctx '')"
# A long prompt is a work request even when it opens like a question.
long="kan du $(printf 'x%.0s' $(seq 1 700))?"
assert_eq "ignores a long prompt" "" "$(cq_ctx "$long")"
# Fail-open: malformed stdin must not produce output or a blocking exit.
printf 'not json\n' | "$cq" >/dev/null 2>&1
assert_eq "malformed payload exits 0" "0" "$?"

# --- 6. generated documents -------------------------------------------------

section "generated docs"
load_fn write_sandbox_claude_md_stub
load_fn write_git_doc
load_fn write_persistence_doc
load_fn write_mount_doc

write_sandbox_claude_md_stub
assert_golden "CLAUDE.md stub" "$CAPTURE_DIR/CLAUDE.md" "CLAUDE.md"

write_git_doc
assert_golden "01-git.md" "$CAPTURE_DIR/01-git.md" "01-git.md"

write_persistence_doc
assert_golden "02-persistence.md" "$CAPTURE_DIR/02-persistence.md" "02-persistence.md"
assert_contains "persistence doc names the output-styles tier" \
    "output-styles" "$CAPTURE_DIR/02-persistence.md"

write_mount_doc "abc1234567" "/test/project" "primary"
assert_golden "mount doc" "$CAPTURE_DIR/mount-abc1234567.md" "mount-primary.md"

# --- 7. seeded skill --------------------------------------------------------

section "managed claude-sandbox skill"
load_fn seed_claude_sandbox_skill
skills="$WORK_DIR/skills-global"
seed_claude_sandbox_skill "$skills"
assert_golden "SKILL.md" "$skills/claude-sandbox/SKILL.md" "SKILL.md"
assert_contains "skill names the output-styles tier" \
    "output-styles" "$skills/claude-sandbox/SKILL.md"

# --- 8. installer completeness ---------------------------------------------

section "installer"
# Every path install.sh copies out of the checkout must exist, or a fresh
# install silently ships without it. This is the guard for adding an
# asset directory: forgetting the install line fails here.
missing=""
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -e "$REPO_ROOT/$rel" ] || missing="$missing $rel"
done < <(grep -oE '\$SOURCE/[A-Za-z0-9._/-]+' "$REPO_ROOT/install.sh" | sed 's|^\$SOURCE/||' | sort -u)
assert_eq "install.sh only references files that exist" "" "$missing"

assert_true "install.sh ships the share/ tree" \
    grep -q 'SOURCE/share' "$REPO_ROOT/install.sh"

# --- 9. assets --------------------------------------------------------------

section "assets"
setup_env
load_fn render_asset
load_fn sed_escape
load_fn render_asset_to
load_fn project_slug_for_path

# Every asset the script asks for must exist in the checkout, or `create`
# aborts. This is the check that catches a rename done on one side only.
requested="$(grep -oE 'render_asset(_to)? [A-Za-z0-9._/-]+' "$SCRIPT" \
    | awk '{print $2}' | sort -u)"
assert_eq "script requests at least one asset" \
    "6" "$(printf '%s\n' "$requested" | grep -c .)"
absent=""
for rel in $requested; do
    [ -f "$REPO_ROOT/share/$rel" ] || absent="$absent $rel"
done
assert_eq "every requested asset exists in share/" "" "$absent"

# And the reverse: an asset nobody renders is dead weight.
orphans=""
while IFS= read -r rel; do
    printf '%s\n' "$requested" | grep -qxF "$rel" || orphans="$orphans $rel"
done < <(cd "$REPO_ROOT/share" && find . -type f | sed 's|^\./||' | sort)
assert_eq "every asset in share/ is rendered by the script" "" "$orphans"

# Placeholders are a closed set: one the renderer does not know would ship
# a literal {{NAME}} into a sandbox, so it must fail instead.
known="$(sed -n 's/.*-e "s|{{\([A-Z_]*\)}}|.*/\1/p' "$SCRIPT" | sort -u)"
unknown=""
while IFS= read -r ph; do
    printf '%s\n' "$known" | grep -qxF "$ph" || unknown="$unknown {{$ph}}"
done < <(grep -rhoE '\{\{[A-Z_]+\}\}' "$REPO_ROOT/share" | tr -d '{}' | sort -u)
assert_eq "every placeholder used in share/ is known to render_asset" "" "$unknown"

# Failure modes, both of which must be loud rather than silent.
assert_false "missing asset fails" render_asset "nope/missing.md"
printf 'x {{NOT_A_PLACEHOLDER}} y\n' > "$WORK_DIR/bad.md"
ASSET_DIR="$WORK_DIR" assert_false "unresolved placeholder fails" render_asset "bad.md"

# A failed render must not clobber a previously good file.
printf 'previous content\n' > "$WORK_DIR/dest.md"
render_asset_to "nope/missing.md" "$WORK_DIR/dest.md" 2>/dev/null
assert_eq "failed render leaves the destination intact" \
    "previous content" "$(cat "$WORK_DIR/dest.md")"

# Substitution must survive metacharacters in the values it splices in.
CONFIG_DIR='/tmp/we&ird|path'
printf -- '{{CONFIG_DIR}}\n' > "$WORK_DIR/meta.md"
assert_eq "escapes sed metacharacters in values" '/tmp/we&ird|path' \
    "$(ASSET_DIR="$WORK_DIR" render_asset "meta.md")"
CONFIG_DIR="/test/config"

# --- summary ----------------------------------------------------------------

teardown_env
printf '\n%s checks, %s failures\n' "$CHECKS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
