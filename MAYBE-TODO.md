# Maybe-TODO

Things we've thought about but deliberately deferred — design ideas
that aren't implemented, decisions made for simplicity that may want
revisiting, and small polish items. Not user-facing documentation —
that lives in `README.md`.

Last updated: 2026-05-10

## Design questions (need usage experience)

### What is the status data actually for?
The reporter publishes `{developer, hostname, timestamp, sessions}`,
but the consumer side is undecided. Initial idea was a desk traffic
light (working / waiting / done). Until a real consumer exists, we
don't know if the payload schema is right — fields like a coarse
state enum (idle/working/awaiting-input/error) might be more useful
than dumping the raw sessions array.

**Revisit when:** the first consumer is built. Likely cue to redesign
the payload.

### Polling vs. hook-driven events
Reporter polls `~/.claude/sessions/*.json` every 15s. Claude Code has
stop/notification hooks that could push precise transitions
(idle → working → done) instead. Hooks would be cleaner and lower
latency, but require installing hook config into the sandbox during
`create`.

**Revisit when:** polling latency or load is annoying, or when we want
sub-second indicator response.

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
