#!/bin/zsh
set -e
# VLC provides a native pause command over its remote-control interface.
if [[ -x /Applications/VLC.app/Contents/MacOS/VLC ]]; then
    PLAYER=/Applications/VLC.app/Contents/MacOS/VLC
elif [[ -x /opt/homebrew/bin/vlc ]]; then
    PLAYER=/opt/homebrew/bin/vlc
elif [[ -x /usr/local/bin/vlc ]]; then
    PLAYER=/usr/local/bin/vlc
else
    PLAYER=$(command -v vlc || true)
fi
if [[ -z "$PLAYER" ]]; then
    echo "Error: VLC not found."
    exit 1
fi
NC=/usr/bin/nc

# Player state shared by all three PopClip actions.
CACHE_DIR="$HOME/Library/Caches/PopClipAzureTTS"
PID_FILE="$CACHE_DIR/player.pid"
PORT_FILE="$CACHE_DIR/player.port"
LOCK_DIR="$CACHE_DIR/player.lock"
STATE_AUDIO="$CACHE_DIR/player.audio"
STATE_SPEED="$CACHE_DIR/player.speed"
STATE_POSITION="$CACHE_DIR/player.position"
STATE_STARTED="$CACHE_DIR/player.started"
STATE_STATUS="$CACHE_DIR/player.status"
mkdir -p "$CACHE_DIR"

# Serialize clicks so two rapid PopClip actions cannot start two players.
acquire_lock() {
    local attempt owner
    for attempt in {1..40}; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            printf '%s\n' "$$" > "$LOCK_DIR/owner"
            trap 'rm -f "$LOCK_DIR/owner"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
            return 0
        fi

        owner=$(<"$LOCK_DIR/owner" 2>/dev/null || true)
        if ! [[ "$owner" =~ '^[0-9]+$' ]] || ! kill -0 "$owner" 2>/dev/null; then
            rm -f "$LOCK_DIR/owner"
            rmdir "$LOCK_DIR" 2>/dev/null || true
            continue
        fi
        sleep 0.05
    done

    echo "Azure TTS is busy."
    return 1
}

# Verify that a PID belongs to this extension's VLC process.
is_our_player() {
    local pid="$1" command
    [[ "$pid" =~ '^[0-9]+$' ]] || return 1
    command=$(ps -p "$pid" -o command= 2>/dev/null) || return 1
    [[ "$command" == "$PLAYER "* && "$command" == *"$CACHE_DIR/"* ]]
}

# A stopped process does not act on SIGTERM until continued. Resume it first,
# request a clean exit, then force it only if it remains alive.
stop_player() {
    local pid="$1" attempt
    is_our_player "$pid" || return 0

    kill -CONT "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    for attempt in {1..20}; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.05
    done
    kill -KILL "$pid" 2>/dev/null || true
}

# Return the current player. If the PID file went stale or disappeared, recover
# the process by inspecting VLC commands that reference our cache directory.
get_player_pid() {
    local pid discovered candidate

    if [[ -r "$PID_FILE" ]]; then
        pid=$(<"$PID_FILE")
        if is_our_player "$pid"; then
            REPLY="$pid"
            return 0
        fi
    fi

    discovered=$(ps -axo pid=,command= | awk -v exe="$PLAYER" -v cache="$CACHE_DIR/" \
        '$2 == exe && index($0, cache) { print $1 }')
    [[ -n "$discovered" ]] || return 1

    # Keep only the newest matching process if an earlier race left extras.
    local -a pids
    pids=("${(@f)discovered}")
    candidate="${pids[-1]}"
    for pid in "${pids[@]}"; do
        if [[ "$pid" != "$candidate" ]]; then
            stop_player "$pid"
        fi
    done

    printf '%s\n' "$candidate" > "$PID_FILE"
    REPLY="$candidate"
    return 0
}

write_player_state() {
    local state_value="$1" audio="$2" speed="$3" position="$4" started="$5"
    printf '%s\n' "$audio" > "$STATE_AUDIO"
    printf '%s\n' "$speed" > "$STATE_SPEED"
    printf '%s\n' "$position" > "$STATE_POSITION"
    printf '%s\n' "$started" > "$STATE_STARTED"
    printf '%s\n' "$state_value" > "$STATE_STATUS"
}

launch_player() {
    local audio="$1" speed="$2" position="$3" port attempt ready

    if get_player_pid; then
        stop_player "$REPLY"
    fi
    rm -f "$PID_FILE"

    for port in {43177..43197}; do
        if ! "$NC" -z 127.0.0.1 "$port" 2>/dev/null; then
            break
        fi
    done
    printf '%s\n' "$port" > "$PORT_FILE"

    nohup "$PLAYER" \
        --intf dummy \
        --extraintf rc \
        --rc-host "127.0.0.1:$port" \
        --no-video \
        --play-and-exit \
        --rate "$speed" \
        --start-time "$position" \
        "$audio" \
        </dev/null \
        >"$CACHE_DIR/player.log" 2>&1 &

    PLAYER_PID=$!
    printf '%s\n' "$PLAYER_PID" > "$PID_FILE"
    disown "$PLAYER_PID" 2>/dev/null || true

    ready=0
    for attempt in {1..60}; do
        if is_our_player "$PLAYER_PID" && "$NC" -z 127.0.0.1 "$port" 2>/dev/null; then
            ready=1
            break
        fi
        sleep 0.05
    done
    if [[ "$ready" != "1" ]]; then
        rm -f "$PID_FILE"
        echo "VLC failed to start."
        return 1
    fi

    write_player_state playing "$audio" "$speed" "$position" "0"
}

send_player_command() {
    local player_command="$1" port
    port=$(cat "$PORT_FILE" 2>/dev/null || true)
    [[ "$port" =~ '^[0-9]+$' ]] || return 1
    printf '%s\n' "$player_command" | "$NC" 127.0.0.1 "$port" -w 1 >/dev/null 2>&1
}

acquire_lock

# VLC's native pause command preserves its internal audio clock and buffers.
if [[ "$POPCLIP_ACTION_IDENTIFIER" == "toggle" ]]; then
    STATUS=$(cat "$STATE_STATUS" 2>/dev/null || true)
    AUDIO=$(cat "$STATE_AUDIO" 2>/dev/null || true)
    SAVED_SPEED=$(cat "$STATE_SPEED" 2>/dev/null || true)
    POSITION=$(cat "$STATE_POSITION" 2>/dev/null || true)
    STARTED=$(cat "$STATE_STARTED" 2>/dev/null || true)

    if get_player_pid; then
        PLAYER_PID="$REPLY"
        if [[ "$STATUS" == "paused" ]]; then
            send_player_command pause
            write_player_state playing "$AUDIO" "$SAVED_SPEED" "$POSITION" "0"
        else
            send_player_command pause
            write_player_state paused "$AUDIO" "$SAVED_SPEED" "$POSITION" "0"
        fi
    elif [[ "$STATUS" == "paused" && -f "$AUDIO" ]]; then
        # Fallback only: restart at the estimated position if the paused PID died.
        launch_player "$AUDIO" "$SAVED_SPEED" "$POSITION"
    else
        rm -f "$PID_FILE"
        echo "Nothing is currently paused."
    fi
    exit 0
fi

# Playback speed is selected by the PopClip action that was clicked.
case "$POPCLIP_ACTION_IDENTIFIER" in
    slow) SPEED="0.8" ;;
    normal|"") SPEED="1.0" ;;
    *) echo "Unknown playback action."; exit 1 ;;
esac

# Settings
REGION="${POPCLIP_OPTION_REGION:-eastus}"
LANG="${POPCLIP_OPTION_LANG:-en-US}"
VOICE="${POPCLIP_OPTION_VOICE:-en-US-JennyMultilingualNeural}"
FORMAT="${POPCLIP_OPTION_FORMAT:-audio-16khz-32kbitrate-mono-mp3}"
TEXT="${POPCLIP_TEXT}"
# Validate speed
if ! [[ "$SPEED" =~ '^(0\.[5-9][0-9]*|1(\.[0-9]+)?|2(\.0+)?)$' ]]; then
    echo "Invalid speed. Use 0.5 to 2.0."
    exit 1
fi

# A stay-visible PopClip session can omit the original text on a later click.
# In that case replay the last cached audio instead of making an empty request.
if [[ -z "$TEXT" ]]; then
    CACHE_FILE=$(cat "$STATE_AUDIO" 2>/dev/null || true)
    if [[ ! -s "$CACHE_FILE" ]]; then
        echo "No previous audio is available."
        exit 1
    fi
    launch_player "$CACHE_FILE" "$SPEED" "0"
    exit 0
fi

# Cache key excludes playback speed
CACHE_KEY=$(printf '%s\0' \
    "$TEXT" \
    "$REGION" \
    "$LANG" \
    "$VOICE" \
    "$FORMAT" \
    | shasum -a 256 | awk '{print $1}')
CACHE_FILE="$CACHE_DIR/$CACHE_KEY.mp3"
# Download only when cache is missing
if [[ ! -s "$CACHE_FILE" ]]; then
    if [[ -z "$POPCLIP_OPTION_KEY" ]]; then
        echo "Azure subscription key is missing."
        exit 1
    fi
    TEMP_FILE=$(mktemp "$CACHE_DIR/.tts.XXXXXXXX")
    # Escape XML special characters
    ESCAPED_TEXT=$(printf '%s' "$TEXT" | \
        sed -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&apos;/g")
    SSML="<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"$LANG\">
    <voice name=\"$VOICE\">$ESCAPED_TEXT</voice>
</speak>"
    # Azure TTS request
    if curl --fail --silent --show-error \
        --connect-timeout 10 \
        --max-time 60 \
        -X POST \
        "https://${REGION}.tts.speech.microsoft.com/cognitiveservices/v1" \
        -H "Ocp-Apim-Subscription-Key: ${POPCLIP_OPTION_KEY}" \
        -H "Content-Type: application/ssml+xml" \
        -H "X-Microsoft-OutputFormat: ${FORMAT}" \
        --data-binary "$SSML" \
        -o "$TEMP_FILE"; then
        if [[ -s "$TEMP_FILE" ]]; then
            mv -f "$TEMP_FILE" "$CACHE_FILE"
        else
            rm -f "$TEMP_FILE"
            exit 1
        fi
    else
        rm -f "$TEMP_FILE"
        exit 1
    fi
fi
# A speed button always starts the selected text from the beginning. Pause and
# resume are handled exclusively by the Pause / Resume action.
launch_player "$CACHE_FILE" "$SPEED" "0"
