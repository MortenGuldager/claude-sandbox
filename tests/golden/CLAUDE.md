# Sandbox runtime environment

You are running inside a `claude-sandbox` Incus container, not on the
host. Runtime details specific to how this sandbox was launched —
mounted project path, forwarded USB devices, forwarded network ports —
live as individual files in `/home/ubuntu/.claude/CLAUDE.d/`. Read every file
there at the start of the session, and re-read it if you suspect the
environment has changed.

Your world here is deliberately narrow: the container is disposable, and
almost nothing you change outside the mounted project survives a rebuild.
What does survive, and why the isolation is intentional, is spelled out
in `/home/ubuntu/.claude/CLAUDE.d/02-persistence.md` and the `claude-sandbox`
skill. Read them before assuming a change will persist or reach beyond
this project.

A small set of always-on rules and facts shared by *every* sandbox may
live in `~/.claude/global-memory/`. If a `MEMORY.md` exists there,
read it at session start and treat it as standing, cross-project user
preference.
