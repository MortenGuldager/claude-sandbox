#!/usr/bin/env bash
# claude-status-reporter — periodically publishes the state of
# ~/.claude/sessions/*.json via a configurable backend.
#
# Settings are read from /etc/claude-status-reporter.env (or the path in
# $REPORTER_CONFIG_FILE). The host-side `claude-sandbox create` writes
# that file based on the user's ~/.config/claude-sandbox/config.

set -u

CONFIG_FILE="${REPORTER_CONFIG_FILE:-/etc/claude-status-reporter.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

REPORTER_BACKEND="${REPORTER_BACKEND:-stdout}"
REPORTER_INTERVAL="${REPORTER_INTERVAL:-15}"
SESSIONS_DIR="${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}"
DEVELOPER="${DEVELOPER_NAME:-unknown}"
HOST_NAME="$(hostname)"

# --- Backends ---------------------------------------------------------------

publish_none() { :; }

publish_stdout() {
    printf '%s\n' "$1"
}

publish_file() {
    local path="${REPORTER_FILE_PATH:-/var/log/claude-status.jsonl}"
    printf '%s\n' "$1" >> "$path"
}

publish_http() {
    local url="${REPORTER_HTTP_URL:-}"
    if [ -z "$url" ]; then
        echo "reporter: REPORTER_HTTP_URL is empty" >&2
        return
    fi
    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -X POST -d "$1" "$url" > /dev/null || true
}

publish_mqtt() {
    local host="${REPORTER_MQTT_HOST:-}"
    local port="${REPORTER_MQTT_PORT:-1883}"
    local topic="${REPORTER_MQTT_TOPIC:-}"
    local user="${REPORTER_MQTT_USER:-}"
    local pass="${REPORTER_MQTT_PASS:-}"
    if [ -z "$host" ] || [ -z "$topic" ]; then
        echo "reporter: REPORTER_MQTT_HOST and REPORTER_MQTT_TOPIC must be set" >&2
        return
    fi
    local args=(-h "$host" -p "$port" -t "$topic" -m "$1" -q 0)
    [ -n "$user" ] && args+=(-u "$user")
    [ -n "$pass" ] && args+=(-P "$pass")
    mosquitto_pub "${args[@]}" 2>/dev/null || true
}

publish() {
    case "$REPORTER_BACKEND" in
        none)   publish_none   "$1" ;;
        stdout) publish_stdout "$1" ;;
        file)   publish_file   "$1" ;;
        http)   publish_http   "$1" ;;
        mqtt)   publish_mqtt   "$1" ;;
        *)      echo "reporter: unknown backend '$REPORTER_BACKEND'" >&2 ;;
    esac
}

# --- Main loop --------------------------------------------------------------

while true; do
    sessions="[]"
    if [ -d "$SESSIONS_DIR" ]; then
        shopt -s nullglob
        files=("$SESSIONS_DIR"/*.json)
        shopt -u nullglob
        if [ "${#files[@]}" -gt 0 ]; then
            sessions="$(jq -s '.' "${files[@]}" 2>/dev/null || echo '[]')"
        fi
    fi

    payload="$(jq -nc \
        --arg dev      "$DEVELOPER" \
        --arg host     "$HOST_NAME" \
        --arg ts       "$(date -Iseconds)" \
        --argjson sess "$sessions" \
        '{developer:$dev, hostname:$host, timestamp:$ts, sessions:$sess}')"

    publish "$payload"
    sleep "$REPORTER_INTERVAL"
done
