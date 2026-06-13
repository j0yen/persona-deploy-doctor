#!/usr/bin/env bash
# tests/run.sh — Shell tests for doctor.sh
# No live config touched. No network. All writes go to TMPDIR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTOR="$REPO_DIR/doctor.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}  $1"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}  $1"
    if [[ -n "${2:-}" ]]; then
        echo "       detail: $2"
    fi
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

# Run doctor and store exit code in EXIT_CODE variable
doctor_run() {
    set +e
    OUTPUT="$("$DOCTOR" "$@" 2>/dev/null)"
    EXIT_CODE=$?
    set -e
}

echo "=== persona-deploy-doctor tests ==="
echo ""

# AC1: --help documents flags and exit codes
echo "--- AC1: --help output ---"
set +e
HELP_OUT="$("$DOCTOR" --help 2>&1)"
set -e
if echo "$HELP_OUT" | grep -q -- '--expect-self-name' && \
   echo "$HELP_OUT" | grep -q -- '--json' && \
   echo "$HELP_OUT" | grep -q 'EXIT CODES' && \
   echo "$HELP_OUT" | grep -q '[^0-9]0[^0-9]' && \
   echo "$HELP_OUT" | grep -q '[^0-9]1[^0-9]' && \
   echo "$HELP_OUT" | grep -q '[^0-9]2[^0-9]'; then
    pass "AC1: --help documents --expect-self-name, --json, and exit codes 0/1/2"
else
    fail "AC1: --help missing required documentation" ""
fi

# AC2: healthy fixture exits 0
echo ""
echo "--- AC2: healthy fixture exits 0 ---"
doctor_run --config "$FIXTURES/healthy.toml" --expect-self-name Clara
if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "AC2: healthy fixture with --expect-self-name Clara exits 0"
else
    fail "AC2: healthy fixture should exit 0, got $EXIT_CODE" "$OUTPUT"
fi

# AC3a: redline=off fixture exits 1 and names redline check
echo ""
echo "--- AC3: redline=off fixture exits 1 ---"
doctor_run --config "$FIXTURES/redline-off.toml" --expect-self-name Clara
if [[ "$EXIT_CODE" -eq 1 ]] && echo "$OUTPUT" | grep -qi 'redline'; then
    pass "AC3a: redline=off exits 1 and names redline check"
else
    fail "AC3a: redline=off should exit 1 and name redline" "exit=$EXIT_CODE output=$OUTPUT"
fi

# AC3b: redline table with action=Off also exits 1
doctor_run --config "$FIXTURES/redline-table-off.toml" --expect-self-name Clara
if [[ "$EXIT_CODE" -eq 1 ]] && echo "$OUTPUT" | grep -qi 'redline'; then
    pass "AC3b: [persona.redline] action=Off exits 1 and names redline check"
else
    fail "AC3b: redline table Off should exit 1 and name redline" "exit=$EXIT_CODE output=$OUTPUT"
fi

# AC4: bad-name fixture exits 1 and names self_name check
echo ""
echo "--- AC4: bad-name fixture exits 1 ---"
doctor_run --config "$FIXTURES/bad-name.toml" --expect-self-name Clara
if [[ "$EXIT_CODE" -eq 1 ]] && echo "$OUTPUT" | grep -qi 'self_name'; then
    pass "AC4: self_name=wintermute exits 1 and names self_name check"
else
    fail "AC4: bad-name should exit 1 and name self_name" "exit=$EXIT_CODE output=$OUTPUT"
fi

# AC5: empty-terms fixture exits 1 and names forbidden_terms check
echo ""
echo "--- AC5: empty-terms fixture exits 1 ---"
doctor_run --config "$FIXTURES/empty-terms.toml" --expect-self-name Clara
if [[ "$EXIT_CODE" -eq 1 ]] && echo "$OUTPUT" | grep -qi 'forbidden_terms'; then
    pass "AC5: empty forbidden_terms exits 1 and names forbidden_terms check"
else
    fail "AC5: empty-terms should exit 1 and name forbidden_terms" "exit=$EXIT_CODE output=$OUTPUT"
fi

# AC6: missing config exits 2
echo ""
echo "--- AC6: missing config exits 2 ---"
doctor_run --config /tmp/no-such-file-persona-doctor-test-$$
if [[ "$EXIT_CODE" -eq 2 ]]; then
    pass "AC6: missing config exits 2"
else
    fail "AC6: missing config should exit 2, got $EXIT_CODE" "$OUTPUT"
fi

# AC7: --json emits valid JSON with healthy bool and drift array
echo ""
echo "--- AC7: --json output ---"
# Test healthy case
doctor_run --config "$FIXTURES/healthy.toml" --expect-self-name Clara --json
VALID_JSON="$(echo "$OUTPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert isinstance(d.get('healthy'), bool), 'healthy must be bool'
    assert isinstance(d.get('drift'), list), 'drift must be list'
    assert 'checked_at' in d, 'checked_at must be present'
    print('ok')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "error: parse failed")"
if [[ "$VALID_JSON" == "ok" ]]; then
    pass "AC7a: --json on healthy fixture emits valid JSON with bool healthy and drift array"
else
    fail "AC7a: --json JSON invalid: $VALID_JSON" "output: $OUTPUT"
fi

# Test drift case JSON
doctor_run --config "$FIXTURES/bad-name.toml" --expect-self-name Clara --json
VALID_JSON="$(echo "$OUTPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    assert d.get('healthy') == False, 'healthy must be false for drift case'
    assert len(d.get('drift', [])) > 0, 'drift must be non-empty for drift case'
    print('ok')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "error: parse failed")"
if [[ "$VALID_JSON" == "ok" ]]; then
    pass "AC7b: --json on drift fixture emits {healthy:false, drift:[...non-empty]}"
else
    fail "AC7b: drift JSON invalid: $VALID_JSON" "output: $OUTPUT"
fi

# AC8: installer does not auto-enable; prints enable command
echo ""
echo "--- AC8: install.sh prints enable command without auto-enabling ---"
if [[ -f "$REPO_DIR/install.sh" ]]; then
    set +e
    INSTALL_OUT="$("$REPO_DIR/install.sh" 2>&1)"
    set -e
    if echo "$INSTALL_OUT" | grep -q 'enable --now'; then
        pass "AC8: install.sh prints 'enable --now' command (not auto-run)"
    else
        fail "AC8: install.sh did not print 'enable --now' command" "$INSTALL_OUT"
    fi
else
    fail "AC8: install.sh not found" ""
fi

# AC9: agorabus event path degrades gracefully when CLI absent
echo ""
echo "--- AC9: agorabus degradation ---"
# doctor.sh doesn't call agorabus directly; verify it runs cleanly with minimal PATH
OLD_PATH="$PATH"
export PATH="/usr/bin:/bin"
doctor_run --config "$FIXTURES/healthy.toml" --expect-self-name Clara
export PATH="$OLD_PATH"
if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "AC9: doctor.sh runs cleanly with agorabus absent from PATH (exit 0 on healthy)"
else
    fail "AC9: doctor.sh failed with agorabus absent" "exit=$EXIT_CODE output=$OUTPUT"
fi

# Summary
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
