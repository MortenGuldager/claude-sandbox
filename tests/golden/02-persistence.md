# Persistent Claude state across sandboxes

This container is disposable: `claude-sandbox destroy create` wipes its OS, installed packages, and anything under `$HOME` that isn't a mount below. That narrowness is deliberate — it stops one project's sandbox from silently altering another's. Only these survive a rebuild, and only the **global** tiers cross between projects:

- **Project tree** — the mounted repo, same path as on the host. Commits and build output persist there.
- **Local skills** `~/.claude/skills/` — writable, **this project only** (host: `/test/config/skills/-test-project/`). Skills you author land here and are invisible to other projects.
- **Local memory** `~/.claude/projects/-test-project/memory/` — writable, **this project only** (host: `/test/config/memory/-test-project/`). `MEMORY.md` is the always-loaded index.
- **Global skills** — **read-only**, shared by every sandbox. They show up as extra entries in `~/.claude/skills/` but you cannot edit them from here (host: `/test/config/skills-global/`).
- **Global memory** `~/.claude/global-memory/` — **read-only**, shared by every sandbox; always-on rules/facts. Read its `MEMORY.md` at session start (host: `/test/config/memory-global/`).
- **Global output styles** `~/.claude/output-styles/` — **read-only**, shared by every sandbox (host: `/test/config/output-styles/`). The active one is set in `settings.json` by `create`; it shapes how you write, so treat it as standing user preference.

You write only to the two *local* tiers. Making something global is the user's call alone: they move it, host-side, from a local dir into the matching global dir. You cannot promote it yourself — that gate is exactly why your reach is limited. If a rule ought to apply everywhere, write it to local memory and *tell the user* it's a promotion candidate.

For what belongs in a skill vs. memory, how to author each, and how promotion works, see the `claude-sandbox` skill.
