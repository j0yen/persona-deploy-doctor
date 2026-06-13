#!/usr/bin/env bash
# doctor.sh — Persona drift health checker for the Jocelyn elder persona
# Exit 0 = healthy, 1 = drift detected, 2 = config unreadable / wmd missing
set -euo pipefail

PROGNAME="$(basename "$0")"
VERSION="0.1.0"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTIONS]

Check that the deployed Jocelyn persona config has not drifted from
the expected state.

OPTIONS:
  --config <path>           Path to brain.toml (default: brain.toml auto-detected)
  --expect-self-name <name> Assert self_name equals this value (default: Clara)
  --expect-wake-word <word> Assert wake_word equals this value (optional check)
  --expect-redline active   Assert redline is not Off (always checked; value must be 'active')
  --json                    Emit JSON: {"healthy":bool,"drift":[...],"checked_at":"<ISO>"}
  --help                    Show this help
  --version                 Show version

EXIT CODES:
  0  All checks passed — persona config is healthy
  1  Drift detected — one or more checks failed; report lists each failing check
  2  Error — config could not be read or wmd is unavailable

CHECKS PERFORMED:
  1. forbidden_terms is non-empty in [persona]
  2. [persona].redline is an active action (not Off or absent)
  3. self_name equals the expected warm name (default: Clara, not 'wintermute')
  4. (optional) wake_word equals expected value if --expect-wake-word is given

JSON OUTPUT (--json):
  {"healthy": true|false, "drift": ["check_name: reason", ...], "checked_at": "2026-..."}

EXAMPLES:
  $PROGNAME --config ~/.config/wintermute/brain.toml --expect-self-name Clara
  $PROGNAME --json --config /tmp/fixture.toml
  $PROGNAME --expect-self-name Clara --expect-wake-word wintermute
EOF
}

# Defaults
CONFIG_PATH=""
EXPECT_SELF_NAME="Clara"
EXPECT_WAKE_WORD=""
JSON_MODE=false
DRIFT=()
EXIT_CODE=0

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --version)
            echo "$PROGNAME $VERSION"
            exit 0
            ;;
        --config)
            shift
            CONFIG_PATH="$1"
            ;;
        --expect-self-name)
            shift
            EXPECT_SELF_NAME="$1"
            ;;
        --expect-wake-word)
            shift
            EXPECT_WAKE_WORD="$1"
            ;;
        --expect-redline)
            shift
            # We only accept "active" as the value; any other value is an error
            if [[ "$1" != "active" ]]; then
                echo "ERROR: --expect-redline only accepts 'active'" >&2
                exit 2
            fi
            ;;
        --json)
            JSON_MODE=true
            ;;
        *)
            echo "ERROR: Unknown flag: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# Auto-detect config path if not given
find_config() {
    local candidates=(
        "$HOME/.config/wintermute/brain.toml"
        "$HOME/wintermute/wintermute-brain/brain.toml"
        "$HOME/.wintermute/brain.toml"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

if [[ -z "$CONFIG_PATH" ]]; then
    if ! CONFIG_PATH="$(find_config)"; then
        if [[ "$JSON_MODE" == true ]]; then
            printf '{"healthy":false,"drift":["config: could not find brain.toml in standard locations"],"checked_at":"%s"}\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            echo "ERROR: Could not find brain.toml in standard locations" >&2
            echo "       Pass --config <path> to specify it explicitly" >&2
        fi
        exit 2
    fi
fi

# Verify config is readable
if [[ ! -f "$CONFIG_PATH" ]]; then
    if [[ "$JSON_MODE" == true ]]; then
        printf '{"healthy":false,"drift":["config: file not found: %s"],"checked_at":"%s"}\n' \
            "$CONFIG_PATH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        echo "ERROR: Config not found: $CONFIG_PATH" >&2
    fi
    exit 2
fi

if [[ ! -r "$CONFIG_PATH" ]]; then
    if [[ "$JSON_MODE" == true ]]; then
        printf '{"healthy":false,"drift":["config: file not readable: %s"],"checked_at":"%s"}\n' \
            "$CONFIG_PATH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        echo "ERROR: Config not readable: $CONFIG_PATH" >&2
    fi
    exit 2
fi

# Parse TOML fields using Python (no cargo, no wmd dependency for parsing)
parse_toml() {
    python3 - "$CONFIG_PATH" <<'PYEOF'
import sys
import tomllib
import json

config_path = sys.argv[1]

try:
    with open(config_path, "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(0)

persona = data.get("persona", {})

# Extract self_name
self_name = persona.get("self_name", "")

# Extract forbidden_terms
forbidden_terms = persona.get("forbidden_terms", [])
if not isinstance(forbidden_terms, list):
    forbidden_terms = []

# Extract redline — can be string or table with 'action' field
redline_raw = persona.get("redline", None)
if redline_raw is None:
    redline_action = "absent"
elif isinstance(redline_raw, str):
    redline_action = redline_raw.lower()
elif isinstance(redline_raw, dict):
    redline_action = str(redline_raw.get("action", "absent")).lower()
else:
    redline_action = str(redline_raw).lower()

# Extract wake_word
wake_word = persona.get("wake_word", "")

out = {
    "self_name": self_name,
    "forbidden_terms_count": len(forbidden_terms),
    "forbidden_terms_empty": len(forbidden_terms) == 0,
    "redline_action": redline_action,
    "wake_word": wake_word,
}
print(json.dumps(out))
PYEOF
}

PARSED="$(parse_toml 2>/dev/null)" || {
    if [[ "$JSON_MODE" == true ]]; then
        printf '{"healthy":false,"drift":["config: failed to parse TOML"],"checked_at":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        echo "ERROR: Failed to parse config: $CONFIG_PATH" >&2
    fi
    exit 2
}

# Check for parse error
PARSE_ERR="$(echo "$PARSED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null || true)"
if [[ -n "$PARSE_ERR" ]]; then
    if [[ "$JSON_MODE" == true ]]; then
        printf '{"healthy":false,"drift":["config: TOML parse error: %s"],"checked_at":"%s"}\n' \
            "$PARSE_ERR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        echo "ERROR: TOML parse error: $PARSE_ERR" >&2
    fi
    exit 2
fi

get_field() {
    echo "$PARSED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))"
}

SELF_NAME="$(get_field self_name)"
FORBIDDEN_TERMS_EMPTY="$(get_field forbidden_terms_empty)"
REDLINE_ACTION="$(get_field redline_action)"
WAKE_WORD="$(get_field wake_word)"

# Check 1: forbidden_terms must be non-empty
if [[ "$FORBIDDEN_TERMS_EMPTY" == "True" ]] || [[ "$FORBIDDEN_TERMS_EMPTY" == "true" ]]; then
    DRIFT+=("forbidden_terms: [persona].forbidden_terms is empty — no forbidden terms configured")
fi

# Check 2: redline must be active (not off/absent)
case "$REDLINE_ACTION" in
    off|absent|"")
        DRIFT+=("redline: [persona].redline is '${REDLINE_ACTION}' — redline guard is not active")
        ;;
    *)
        # Any non-off, non-absent value means redline is configured (active)
        ;;
esac

# Check 3: self_name must equal expected name and not be 'wintermute'
if [[ -z "$SELF_NAME" ]]; then
    DRIFT+=("self_name: [persona].self_name is absent or empty — expected '${EXPECT_SELF_NAME}'")
elif [[ "$SELF_NAME" == "wintermute" ]]; then
    DRIFT+=("self_name: [persona].self_name is 'wintermute' — persona has not been renamed from the default")
elif [[ "$SELF_NAME" != "$EXPECT_SELF_NAME" ]]; then
    DRIFT+=("self_name: [persona].self_name is '${SELF_NAME}' — expected '${EXPECT_SELF_NAME}'")
fi

# Check 4 (optional): wake_word must equal expected value
if [[ -n "$EXPECT_WAKE_WORD" ]]; then
    if [[ "$WAKE_WORD" != "$EXPECT_WAKE_WORD" ]]; then
        DRIFT+=("wake_word: [persona].wake_word is '${WAKE_WORD}' — expected '${EXPECT_WAKE_WORD}'")
    fi
fi

# Determine health
CHECKED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ ${#DRIFT[@]} -eq 0 ]]; then
    HEALTHY=true
    EXIT_CODE=0
else
    HEALTHY=false
    EXIT_CODE=1
fi

# Output
if [[ "$JSON_MODE" == true ]]; then
    # Build JSON array of drift items
    DRIFT_JSON="["
    FIRST=true
    for d in "${DRIFT[@]}"; do
        if [[ "$FIRST" == true ]]; then
            FIRST=false
        else
            DRIFT_JSON+=","
        fi
        # Escape for JSON
        ESCAPED="$(echo "$d" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().rstrip()))")"
        DRIFT_JSON+="$ESCAPED"
    done
    DRIFT_JSON+="]"
    printf '{"healthy":%s,"drift":%s,"checked_at":"%s"}\n' \
        "$HEALTHY" "$DRIFT_JSON" "$CHECKED_AT"
else
    if [[ "$HEALTHY" == true ]]; then
        echo "OK  persona config is healthy (checked: $CONFIG_PATH)"
    else
        echo "DRIFT detected in $CONFIG_PATH (checked at $CHECKED_AT)"
        echo ""
        echo "Failing checks:"
        for d in "${DRIFT[@]}"; do
            echo "  FAIL  $d"
        done
        echo ""
        echo "Run with --json for machine-readable output."
    fi
fi

exit "$EXIT_CODE"
