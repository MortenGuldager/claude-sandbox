# claude-sandbox

A small wrapper around [Incus](https://linuxcontainers.org/incus/) that
spins up disposable containers for running
[Claude Code](https://github.com/anthropics/claude-code) against a
project directory mounted from the host. Optionally maps a USB/serial
device into the sandbox so Claude can talk to attached hardware.

A companion service inside the sandbox polls Claude's session state
and publishes it via a configurable backend (stdout, file, MQTT, HTTP),
so you can drive a desk indicator, dashboard, or whatever else.

> **Renamed from `ai-sandbox` on 2026-05-10.** This was originally
> framed as a generic AI sandbox, but in practice it only ever
> supported Claude Code — the generic naming was aspirational. It is
> now explicitly a Claude sandbox. If you have an older install, see
> [Migration from `ai-sandbox`](#migration-from-ai-sandbox) below. If a
> different agent ever needs the same treatment, fork this project
> rather than re-genericize it.

## Why

- Keep Claude (and any tools it installs or scripts it runs) off your
  host filesystem.
- Mount only the project directory you care about; everything else stays
  out of reach.
- Make hardware access opt-in per device.
- Get a status feed out of the sandbox without having to read its logs
  manually.

## Prerequisites

On the host:

- [Incus](https://linuxcontainers.org/incus/docs/main/installing/)
- `bash`, `curl`, `jq`, `udevadm`, `md5sum`, `sha256sum` (all standard
  on most distros)

The first `create` builds a cached base image with Node.js, Claude
Code, and the reporter; subsequent `create`s launch from that base in
seconds. See [Base image caching](#base-image-caching) below.

## Install

Clone this repo and run the installer as root:

```sh
git clone https://github.com/MortenGuldager/claude-sandbox.git
cd claude-sandbox
sudo ./install.sh
```

This copies the source to `/opt/claude-sandbox` and adds
`/usr/local/bin/claude-sandbox` as a symlink. To uninstall:

```sh
sudo /opt/claude-sandbox/uninstall.sh
```

The uninstaller leaves your config (`~/.config/claude-sandbox/`) and
any running sandbox containers alone.

## Quickstart

```sh
cd /path/to/your/project
CLAUDE_SANDBOX_AUTH=sk-... \
    claude-sandbox create    # launches a container, mounts the project,
                             # installs Claude Code, starts the reporter
claude-sandbox map ttyACM0   # (optional) pass a USB serial device through
claude-sandbox shell         # drop into the sandbox as user `ubuntu`
# ... work ...
claude-sandbox destroy       # nuke the container
```

Commands chain — `claude-sandbox destroy create map=ttyACM0 shell`
tears the container down and brings a fresh one up in one go. The
chain aborts on the first failure.

`CLAUDE_SANDBOX_AUTH` is forwarded into the sandbox as
`ANTHROPIC_AUTH_TOKEN` (the variable Claude Code looks for). It is
deliberately *not* called `ANTHROPIC_AUTH_TOKEN` on the host: a host
token would silently change how a host-side `claude` CLI authenticates
(token vs. OAuth, with subtly different permissions). Keeping the
sandbox-only name avoids that.

If you don't set it, `create` warns and proceeds — useful when you
just want a shell with the project mounted and don't need Claude
auth'd yet. Set it in your shell profile, or pass it inline as above.

The container name is derived from your project path, so multiple
checkouts of the same repo each get their own sandbox.

## Running Claude inside the sandbox

Two ways to invoke it:

- `claude` — default. Prompts for permission on tool calls, like a
  host install.
- `yolo-claude` — alias for `claude --dangerously-skip-permissions`.
  Skips all prompts; the sandbox isolation is the load-bearing
  protection. Before using it, make sure no identity keys (SSH, GPG,
  cloud credentials, GitHub tokens) have leaked into the mounted
  project directory — anything inside the mount is fair game for a
  prompted-or-tricked agent.

## Base image caching

The first `create` is slow (~90 s) because it builds a base image with
all the heavy bits: `apt upgrade`, Node.js, `@anthropic-ai/claude-code`,
the reporter assets. That image is published to the local Incus image
store under an alias like `claude-sandbox-base-<hash>`. Subsequent
`create`s launch from it in seconds.

The hash is a digest of the inputs that produced the image:

- the source image (`SANDBOX_IMAGE`),
- the package list,
- the contents of the reporter `.sh` and `.service` files,
- a schema version baked into the script.

Change any of those — pin a different Ubuntu, edit the reporter — and
the next `create` notices the hash drift and rebuilds. Nothing else
needs to change. The old base lingers until you remove it.

This is the same idea as a Docker layer keyed off its build context,
collapsed to a single layer on purpose: one cached image solves
~99 % of the wait, and the source-of-truth is the script itself, not
a separate `Dockerfile`-shaped artifact you'd have to keep in sync.

### Refreshing and cleanup

`apt upgrade` runs at base-build time, not on every `create`, so a
months-old base will install months-old packages into new sandboxes.
`create` warns when the base is older than 30 days; refresh it
explicitly:

```sh
claude-sandbox bases          # list cached base images with age and status
claude-sandbox rebuild-base   # rebuild the base for the current hash
claude-sandbox gc             # remove cached bases that don't match the current hash
```

Sandboxes already running off an older base keep working; they just
won't pick up the new packages until you `destroy` and `create` again.

## Configuration

All settings have defaults; a config file is only needed to override
them. Copy the example:

```sh
mkdir -p ~/.config/claude-sandbox
cp /opt/claude-sandbox/config.example ~/.config/claude-sandbox/config
```

The file is sourced by bash. See `config.example` for the full list of
settings and their defaults. Highlights:

| Setting                  | Default                       | Notes                                                                |
| ------------------------ | ----------------------------- | -------------------------------------------------------------------- |
| `SANDBOX_IMAGE`          | `images:ubuntu/24.04`         | Any Incus-compatible image.                                          |
| `SANDBOX_PROJECT_PATH`   | `/home/ubuntu/project`        | Where your project mounts inside the sandbox.                        |
| `REPORTER_BACKEND`       | `stdout`                      | One of: `none`, `stdout`, `file`, `mqtt`, `http`.                    |
| `REPORTER_KEEPALIVE`     | `60`                          | Seconds between keep-alive reports (changes are sent immediately).   |

The auth token is read from the `CLAUDE_SANDBOX_AUTH` environment
variable, not from the config file — see [Quickstart](#quickstart).

## Status reporter

A systemd service inside the sandbox runs `claude-status-reporter.sh`,
which watches `~/.claude/sessions/` via inotify and publishes a payload
whenever the aggregated status changes. A keep-alive is also emitted
every `REPORTER_KEEPALIVE` seconds (default 60) so a subscriber that
was offline at boot still learns the current state.

Payload:

```json
{
  "sessions": {
    "c632fc39-11d4-4d63-9dda-74d14706f07b": "busy",
    "9c0dd5a5-1e3d-4af8-b4e5-d43975c9b38e": "idle"
  }
}
```

`sessions` is a map from `sessionId` to `status`, built from
`~/.claude/sessions/*.json` (empty object when no sessions exist).
Consumers should key off `sessionId`, not position — two sandboxes
publishing to the same subscriber will not collide on slot 0.
Identifying info (developer, hostname) is intentionally omitted —
encode it in the MQTT topic / HTTP URL.

### Backends

- **`none`** — disabled.
- **`stdout`** *(default)* — writes to the journal:
  `incus exec <container> -- journalctl -u claude-status-reporter -f`.
- **`file`** — appends one JSON line per report to `REPORTER_FILE_PATH`.
- **`mqtt`** — publishes via `mosquitto_pub` with `-r` (retained), so
  late subscribers immediately receive the last status. The installer
  adds `mosquitto-clients` to the container.
- **`http`** — POSTs `application/json` to `REPORTER_HTTP_URL`.

### Public MQTT brokers

If you point the MQTT backend at a public broker
(`test.mosquitto.org`, `broker.hivemq.com`, ...), assume your data is
visible to the world. Pick a topic that is not guessable — a UUID is a
reasonable default. For anything you would rather not broadcast, run
your own broker.

## Migration from `ai-sandbox`

If you have an install from before the rename:

1. Uninstall the old version:
   ```sh
   sudo /opt/ai-sandbox/uninstall.sh
   ```
2. Move your config (if you had one):
   ```sh
   mv ~/.config/ai-sandbox ~/.config/claude-sandbox
   ```
3. Rename your env var: `AISB_CLAUDE_AUTH` → `CLAUDE_SANDBOX_AUTH`
   (update your shell profile).
4. Existing `aisb-*` sandbox containers are not touched by the new
   CLI — it uses the prefix `csb-` instead. You can keep using the
   old ones via raw `incus exec`, or destroy them and recreate:
   ```sh
   incus list | grep '^| aisb-'
   incus delete -f <name>
   ```
5. Old `ai-sandbox-base-*` cached base images become orphans. List
   and delete:
   ```sh
   incus image list local: | grep ai-sandbox-base-
   incus image delete local:ai-sandbox-base-<hash>
   ```
6. Install the new version (see [Install](#install)).

The internal layout (status reporter unit, env file at
`/etc/claude-status-reporter.env`, mount paths inside the container)
is unchanged — those names were already Claude-specific.

## Project layout

```
bin/claude-sandbox                      # host-side CLI
container/claude-status-reporter.sh     # pushed into the sandbox
container/claude-status-reporter.service
config.example                          # documented settings
install.sh / uninstall.sh
```

## License

[Unlicense](https://unlicense.org/) — public domain. See `LICENSE`.
