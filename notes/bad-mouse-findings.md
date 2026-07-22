# Claude Code "dum mode" — mouse tracking breaks selection/scroll in claude-sandbox

Self-contained findings doc. Belongs in the **claude-sandbox launcher project**, not in a
scratch dir. Investigated 2026-06-18 / updated 2026-06-19 / 2026-06-21.

## TL;DR — there are TWO separate hijacks, fixed by TWO env vars

| Symptom | Mechanism | Fix |
|---|---|---|
| Selection/copy stops, wheel slow/line-by-line | claude turns on **mouse reporting** (`?1000/1002/1003/1006h`), server-flag driven | `CLAUDE_CODE_DISABLE_MOUSE=1` |
| Copy works, but **wheel cycles prompt history** instead of scrollback; PageUp/Dn OK | claude switches to the **alternate screen buffer** for its fullscreen renderer; on the alt screen the terminal's *alternate scroll* turns the wheel into Up/Down arrows | `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` |

Both are now exported from the base image's `~/.bashrc` (commits "Disable claude mouse
capture…" + the alternate-screen follow-up; `BASE_SCHEMA_VERSION=7`). The sections below are
the original mouse-reporting investigation; the alt-screen part is at the bottom.

## Symptom ("dum mode")

While `claude` is running inside a claude-sandbox (Incus) container, attached from
xfce4-terminal / xterm on a Linux desktop host:

- Mouse text-selection no longer copies — double-click does nothing.
- Mouse-wheel scrolling becomes slow / line-by-line instead of normal terminal scrollback.
- Exit `claude` → back to bash → behaviour normalizes.
- Holding **Shift** always works (xterm Shift-override) — Shift+drag to select/copy,
  Shift+wheel or Shift+PageUp/Down for scrollback.

It seemed random because a window is "good" only until it caches the trigger flag, then
goes dumb (see root cause).

## Root cause (proven, not guessed)

It is Claude Code turning on **xterm mouse reporting** (`\x1b[?1000h` / `1002` / `1003` /
`1006`), driven by a **server-side GrowthBook feature flag** that gets cached locally.

- A/B test across two live 2.1.181 sandboxes (2026-06-18): NOT the claude version (both good
  and dumb containers ran 2.1.181), NOT window size, NOT diff rendering.
- A fresh container has **0 cached flags** in `~/.claude.json` and behaves normally
  (mouse tracking off). Once claude fetches & caches the flags (the dumb container had **323**),
  mouse reporting turns on.

### Exact culprit key

In `~/.claude.json`, under `cachedGrowthBookFeatures`:

```
"tengu_pewter_brook": true
```

Confirmed 2026-06-18 by automated binary search + necessary/sufficient test:

- Remove it from the full 323-flag set → **good** mouse.
- Set **only** it `true` → **dumb** mouse.
- Set **only** it `false` → **good** mouse.

Ruled out (tested, innocent): `tengu_native_cursor`, `tengu_xterm_atlas_reset`.

## Where `.claude.json` lives — NOT host-mounted

Confirmed 2026-06-19 from the in-container mount table. Only **three** host directories are
mounted into a sandbox:

| Inside container | Host path |
|---|---|
| `/home/you/tmp/bar` (project dir) | same |
| `~/.claude/projects/<slug>/memory` | `/home/you/.config/claude-sandbox/memory/<slug>/` |
| `~/.claude/skills` | `/home/you/.config/claude-sandbox/skills/` |

`~/.claude.json` (the file with `cachedGrowthBookFeatures`) is **NOT** in that list. It lives
on each container's ephemeral rootfs and dies on `destroy`. Consequences:

- You **cannot** grep one host directory to inspect/patch all sandboxes.
- Go per-running-container via `incus` (see below). Only RUNNING containers are reachable.

## Fixes, best → most drastic

### 1. Env var (candidate — NOT proven reliable)

```sh
export CLAUDE_CODE_DISABLE_MOUSE=1
```

Undocumented (not in `--help`), referenced in GitHub issues. In a 2026-06-18 headless detector
run it turned mouse tracking OFF even with the dumb flag set. **However** 2026-06-19 the user
hit dum mode while "nogen lunde" sure this var WAS set in the affected container — so treat it
as **unconfirmed**, not bulletproof.

If dum mode recurs with the var supposedly set, FIRST verify it's actually exported *in the
shell that launched `claude`* — not just in the launcher:

```sh
echo $CLAUDE_CODE_DISABLE_MOUSE   # run inside the dumb pane itself
```

Cheap, no file patching, survives server flag re-fetch. Only cost: disables ALL TUI mouse
interaction (which is the goal here). Best applied in the sandbox shell profile / `csb`
launcher so every new container inherits it.

### 2. Flag patch (per container, targets the proven culprit)

Before `exec claude`, patch `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` to set
`cachedGrowthBookFeatures.tengu_pewter_brook=false` and bump `cachedGrowthBookFeaturesAt` to
now (delays server re-fetch). Wrapper lived at `~/bin/cc`. NOT 100% durable — a mid-session
re-fetch can restore `true`.

Patch all running sandboxes from the **host**:

```sh
for c in $(incus list -c n --format csv | grep '^csb-'); do
  incus exec "$c" -- python3 - <<'PY'
import json, time, os
p = os.path.expanduser("~/.claude.json")
d = json.load(open(p))
f = d.setdefault("cachedGrowthBookFeatures", {})
if f.get("tengu_pewter_brook") is True:
    f["tengu_pewter_brook"] = False
    d["cachedGrowthBookFeaturesAt"] = int(time.time()*1000)
    json.dump(d, open(p, "w"))
    print("patched")
else:
    print("nothing to do")
PY
done
```

Inspect (read-only) across all running sandboxes:

```sh
for c in $(incus list -c n --format csv | grep '^csb-'); do
  echo "=== $c ==="
  incus file pull "$c/home/ubuntu/.claude.json" - 2>/dev/null \
    | grep -o '"tengu_pewter_brook":[a-z]*'
done
```

### 3. CLAUDE_CONFIG_DIR / Shift (bombproof fallbacks)

- `CLAUDE_CONFIG_DIR=/some/fixed/empty/dir claude` → relocated empty config, 0 cached flags.
- Shift+drag / Shift+wheel always works regardless of flag state.

### 4. Rebuild the sandbox (works, too drastic)

`csb destroy create auth=okapi yolo` → fresh `~/.claude.json` with 0 cached flags → normal
mouse. Memory & skills are host-mounted so nothing is lost. Downside: dum mode returns once
claude re-fetches the flags; throws away the whole container for a one-line config issue.

## DANGER — do not delete `~/.claude`

Do NOT `mv`/`rm` `~/.claude` to test. `~/.claude/skills` and
`~/.claude/projects/<slug>/memory` are bind-mounts to host data shared across ALL sandboxes;
`rm -rf ~/.claude` deletes the real host skills/memory through the mounts. Use
`CLAUDE_CONFIG_DIR=/tmp/dir` for isolated diagnostics instead.

## Diagnostic harness (how the flag was found)

- Clean harness: `CLAUDE_CONFIG_DIR=/tmp/dir claude` runs with a relocated empty config
  (`/tmp/dir/.claude.json`); original `~/.claude` untouched. Empty = good; copy the real
  323-flag `.claude.json` in = dumb. Bisect single flags by editing `cachedGrowthBookFeatures`
  in that copy. Caveat: claude may re-fetch & overwrite local edits on startup.
- Headless mouse-on detector: launch `claude` (WITHOUT `--dangerously-skip-permissions`, else
  a second "Bypass Permissions" prompt blocks) in a Python `pty.fork`; answer the DA1 query
  `\x1b[c` → `\x1b[?62;...c`; send `\r` at ~3s to clear the trust prompt; grep captured output
  for `\x1b[?(1000|1002|1003|1006)h` = mouse ON. Scrub `CLAUDE*` / `AI_AGENT` env from the
  child.

## Upstream tracking (for +1 / bug report)

- #61936 — mouse tracking breaks selection/copy on Linux (closest match)
- #43942 — request opt-out setting
- #62699, #63500 — related
- #23581 — disable mouse tracking, closed as duplicate, unimplemented
- No official toggle exists as of this writing.

## Open question / next time it happens

Env var #1 may not be sufficient on its own (2026-06-19 observation). When it recurs:
1. `echo $CLAUDE_CODE_DISABLE_MOUSE` inside the dumb pane.
2. Check `cachedGrowthBookFeatures.tengu_pewter_brook` in that container's `~/.claude.json`.
3. That A/B settles whether the env var truly fails or just wasn't in the launching shell.

## Second hijack — wheel scrolls prompt history (alternate screen), 2026-06-21

After `CLAUDE_CODE_DISABLE_MOUSE=1` landed in the base image, a *different* symptom remained:

- Copy/selection works fine (mouse reporting is genuinely off — verified: 0 cached
  GrowthBook flags, `tengu_pewter_brook` absent, env var present in claude's `/proc/<pid>/environ`).
- But sometimes the **mouse wheel stops scrolling the terminal scrollback** and instead each
  notch acts like an Up/Down arrow → it **cycles the prompt input history**. PageUp/PageDown
  and Shift+wheel still work. "Window works fine until something goes wrong, then changes."

### Root cause (not mouse reporting — the alternate screen)

Claude Code has two renderers:
- **Classic / inline** (default): conversation prints on the main screen, so the wheel drives
  the terminal's own scrollback. This is "good mode."
- **Fullscreen**: switches to the terminal **alternate screen buffer** (`\x1b[?1049h`).
  The alt screen has no scrollback, and most terminals (xterm/xfce4-terminal) honour
  *alternate scroll mode* — they translate wheel-up/down into `ESC[A`/`ESC[B` (arrow keys)
  and hand them to the app. Claude's prompt box reads those as history navigation. Selection
  is independent of the alt screen, so copy keeps working — exactly the observed split.

The "random trigger" is claude flipping into the fullscreen renderer mid-session. Fullscreen
is being rolled out gradually (the binary contains `CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL`),
so — like the GrowthBook story above — a server-side decision can change window behaviour
without any local change. Confirms with upstream issues #64214, #65833 (Linux wheel →
arrow keys / history on the alt screen).

### Relevant env vars (verified present in the `claude.exe` binary, 2026-06-21)

`grep -aoE 'CLAUDE_CODE_[A-Z_]{3,}' claude.exe` confirms these are real, not guessed:

| Var | Effect |
|---|---|
| `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` | **The fix.** Forces the classic inline renderer; no alt screen → wheel always drives native scrollback. |
| `CLAUDE_CODE_NO_FLICKER=1` | *Enables* fullscreen/alt-screen rendering — do **not** set. |
| `CLAUDE_CODE_SCROLL_SPEED` | Wheel scroll multiplier (cosmetic). |
| `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL`, `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT` | Related rendering knobs, not needed here. |

`CLAUDE_CODE_DISABLE_MOUSE` only stops mouse *reporting*; it does nothing about the alt
screen — hence the partial fix and the lingering wheel-to-history bug.

### Fix (applied)

Export `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` from the base image's `~/.bashrc`, next to
the existing `CLAUDE_CODE_DISABLE_MOUSE=1`; `BASE_SCHEMA_VERSION` bumped to **7** to force a
rebuild. Like the env-var approach for the first hijack, this is immune to server-flag
re-fetch (no `.claude.json` patching). Cost: claude never uses the fullscreen renderer —
acceptable, the inline renderer is what keeps native scrollback working anyway.

Immediate relief without a rebuild: append the export to the running container's `~/.bashrc`
and restart `claude` (env is read at launch).
