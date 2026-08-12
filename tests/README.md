# Tests

Characterisation tests, written to guard the move of embedded payloads
out of `bin/claude-sandbox` and into files. They pin what a sandbox
receives, so the refactor is allowed to change *where* content lives but
not *what* it says.

```bash
tests/run.sh                    # run everything
UPDATE_GOLDEN=1 tests/run.sh    # accept intentional content changes
SCRIPT=/tmp/other.sh tests/run.sh   # run against a modified copy
```

Exit code is 0 only when every check passes.

## What is covered

- `bin/claude-sandbox`, `install.sh`, and `uninstall.sh` parse.
- The seeded output style, byte-for-byte, plus its frontmatter: Claude
  Code validates output-style frontmatter with a strict schema and drops
  the style silently on an unknown key, so the accepted keys are pinned.
- That `SANDBOX_OUTPUT_STYLE`'s default still matches the style's `name:`
  field. If those drift, every `create` warns and no style is applied.
- Style-name lookup: by filename, by frontmatter name, quoted names,
  names containing regex metacharacters, and the empty and missing
  directory cases.
- The `settings.json` merge, run for real through `jq`: selecting a
  style, clearing it, refusing an unknown one, and creating the file when
  absent, all while preserving unrelated keys.
- The `SessionStart` hook, byte-for-byte, plus its behaviour: it must
  emit `hookSpecificOutput.additionalContext` (plain stdout is not added
  to context) and stay silent on an empty index.
- The generated `CLAUDE.md` stub, `01-git.md`, `02-persistence.md`, the
  mount doc, and the managed `claude-sandbox` skill, byte-for-byte.
- That `install.sh` only copies paths that exist and ships `share/`.
- The `share/` assets: every asset the script renders exists, every asset
  present is rendered by something, and every `{{PLACEHOLDER}}` used is
  one the renderer knows.
- The renderer's failure modes: a missing asset and an unresolved
  placeholder both fail, a failed render leaves the destination file
  untouched, and values containing `&` or `|` survive substitution.

## What is not covered

Anything that needs the Incus daemon: base-image build, container
create/destroy, mounts, device passthrough, port forwarding, timezone and
DNS resolution, and the auth-token plumbing. The suite therefore runs
anywhere, including inside a sandbox, but it cannot tell you that
`create` works. Verify that on the host with a real
`csb destroy create`.

Nor does it test Claude Code itself: that the style is picked up and
actually shortens output is an empirical question, checked by running
`claude -p --settings '{"outputStyle":"STE100"}'` against a prompt.

## How the harness works

`bin/claude-sandbox` cannot be sourced: its top level resolves the cwd,
derives a container name, and may reach the network for the reporter SHA.
So `load_fn` lifts single function definitions out of the file by name
and evals them, against a stubbed `incus` and a stubbed container file
writer. The `incus exec ... bash -c` stub runs the in-container snippets
locally under a scratch `HOME`, which is what makes the `jq` merges
testable rather than merely recorded.

`load_fn` relies on the file's layout: a definition starts at column 1 as
`name() {` and ends on a line that is exactly `}`. Keep it that way, or
the harness stops finding functions.

The suite is checked for teeth by mutation: reword the style, drift the
default style name, break the hook's JSON wrapper, or break the `jq`
quoting, and the relevant checks fail.
