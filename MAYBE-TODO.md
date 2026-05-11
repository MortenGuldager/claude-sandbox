# Maybe-TODO

Things we've thought about but deliberately deferred — design ideas
that aren't implemented, decisions made for simplicity that may want
revisiting, and small polish items. Not user-facing documentation —
that lives in `README.md`.

Last updated: 2026-05-11

## Design questions (need usage experience)

### Reporter install requires root, but the reporter does not need it
After extracting `claude-status-reporter` to its own repo, its
`install.sh` still writes to `/usr/local/bin`, `/etc/systemd/system`,
and runs `systemctl daemon-reload --enable`. All of that needs root.
The reporter itself runs as user `ubuntu` and only reads
`~/.claude/sessions/` — purely per-user state.

A systemd *user* unit (`~/.config/systemd/user/...`,
`systemctl --user enable`) would fit naturally and drop the root
requirement entirely. Two phases:

1. **In `claude-status-reporter`:** offer a user-mode install (either a
   `--user` flag on `install.sh` or a separate `install-user.sh`) that
   installs and enables as the current user. Keep system-wide install
   for callers that genuinely want it.
2. **In `claude-sandbox`:** switch `build_base_image` to invoke the
   user-mode install, so the reporter no longer needs root inside the
   build container. This is one step in the larger arc of stripping
   privilege from the sandbox itself — see also the
   `security.privileged=true` note below.

**Revisit when:** doing the reporter side is the natural next step on
the reporter repo; the sandbox change follows once the reporter
supports user-mode install.

### MQTT topic default
Currently the topic must be explicitly set; an empty topic makes the
backend log an error. Alternative: auto-generate a UUID on first
`create` and write it back into `~/.config/claude-sandbox/config`.
More magic, less friction.

**Revisit when:** someone (likely us) sets up MQTT for real and finds
the manual topic step annoying.

### Multi-layer base image
The base is a single published image, hashed over its full input set.
That means changing one package re-runs the whole pipeline (apt
upgrade, NodeSource, npm install of claude-code) — currently ~90 s,
because cache granularity is "all or nothing".

A two-layer version would be closer to Docker's model: one image for
OS + apt-upgrade + apt packages, another image built on top with the
npm step. Small recipe changes would only invalidate the relevant
layer.

Deliberately not implemented: the bookkeeping for two chained images
(two hashes, two publish steps, two GC paths) is more code than the
single layer, and a single layer already eats ~99 % of the wait. The
missing 1 % is "I bumped one package".

**Revisit when:** the base changes often enough that 90-second
rebuilds become a real annoyance.

## Polish (small, do when convenient)

### Agent-created files outside the project mount are invisible from the host
The sandbox deliberately mounts only the project directory; anything
created elsewhere inside the container (e.g. a sibling project) lives
only inside the container and has to be `incus exec`-extracted by hand.
Surfaced 2026-05-11 when claude-status-reporter was first scaffolded
as a sibling directory inside the sandbox — technically the right place
to put it, but invisible from outside until manually copied out.

Options if this becomes a recurring pain:
- Document the limitation prominently so agent prompts default to
  creating sibling projects inside the mount.
- Add a `claude-sandbox export <container-path> <host-path>` command
  for explicit one-shot transfer.
- Optional second mount for a host-side scratch area.

**Revisit when:** the same manual extraction is needed a second time.

### End-to-end verification
`create` and `shell` were exercised on a real Incus host during the
base-image-caching refactor (2026-05-10). Still unverified end-to-end:
`bases`, `gc`, `rebuild-base`, `destroy`, the 30-day age warning, the
USB/serial `map` flow, and all four reporter backends.

**Revisit when:** before the first public push, or earlier if any of
the above paths is touched.

### Privileged-container note in README
`incus launch ... -c security.privileged=true` is required for USB
passthrough but not currently called out as a security trade-off.
Worth a sentence in the README so users know what they're agreeing to.

### Dependency preflight in `bin/claude-sandbox`
The CLI assumes `incus`, `jq`, `curl`, `udevadm`, `md5sum`,
`sha256sum`, and `numfmt` are installed; it fails midway if they are
not. A small check at the top of the script with a clear error message
would be friendlier. (`sha256sum` and `numfmt` were added during the
base-caching work — both ship with coreutils, so realistically only
`incus`, `jq`, `curl`, and `udevadm` are at risk.)

## Release process (do when actually releasing)

### Git init and GitHub repo
The directory is not a git repo yet. Needs `git init`, first commit,
`gh repo create`.

### GitHub meta files
No `CHANGELOG.md`, `CONTRIBUTING.md`, issue/PR templates, or GitHub
Actions. Probably overkill for a project of this size, but worth
choosing deliberately rather than by default.

### Visual demo in README
No screenshot or asciicast. A short `asciinema` recording of
`create → shell → destroy` would communicate the value better than the
current prose-only README.
