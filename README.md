# persona-deploy-doctor

Persona drift health checker for the Jocelyn elder persona on wintermute.

Once `persona-deploy-jocelyn` activates the elder persona, nothing prevents
`brain.toml` from drifting — a stray edit, a config reset, or a
fresh-box re-provision can quietly drop `forbidden_terms`, flip `redline`
back to `Off`, or reset `self_name` to `wintermute`. Nobody notices until
Jocelyn hears the word "computer."

`persona-deploy-doctor` catches this silently, loudly, and on a schedule.

## What healthy looks like

```
$ doctor.sh --expect-self-name Clara --config ~/.config/wintermute/brain.toml
OK  persona config is healthy (checked: ~/.config/wintermute/brain.toml)
$ echo $?
0
```

All four checks passed:
1. `[persona].forbidden_terms` is non-empty
2. `[persona].redline` is an active action (not `Off` or absent)
3. `[persona].self_name` equals the expected warm name (`Clara`, not `wintermute`)
4. (optional) `[persona].wake_word` equals expected value if `--expect-wake-word` is given

## How to read drift output

```
$ doctor.sh --expect-self-name Clara --config /tmp/broken.toml
DRIFT detected in /tmp/broken.toml (checked at 2026-06-13T12:00:00Z)

Failing checks:
  FAIL  redline: [persona].redline is 'off' — redline guard is not active
  FAIL  self_name: [persona].self_name is 'wintermute' — persona has not been renamed from the default

Run with --json for machine-readable output.
$ echo $?
1
```

Exit codes:
- `0` — all checks passed, persona is healthy
- `1` — drift detected, report lists each failing check by name
- `2` — error: config not found/readable, or TOML parse failure

## Machine-readable output

```
$ doctor.sh --config /tmp/fixture.toml --expect-self-name Clara --json
{"healthy":true,"drift":[],"checked_at":"2026-06-13T12:00:00Z"}
```

On drift:
```json
{
  "healthy": false,
  "drift": [
    "redline: [persona].redline is 'off' — redline guard is not active"
  ],
  "checked_at": "2026-06-13T12:00:00Z"
}
```

## Usage

```
doctor.sh [OPTIONS]

OPTIONS:
  --config <path>           Path to brain.toml (default: auto-detected)
  --expect-self-name <name> Assert self_name equals this value (default: Clara)
  --expect-wake-word <word> Assert wake_word equals this value (optional)
  --expect-redline active   Assert redline is not Off (always checked)
  --json                    Emit JSON output
  --help                    Show help
  --version                 Show version
```

## Enable the daily timer

Install units:

```bash
bash install.sh
```

This prints the enable command but does **not** auto-enable. Run it yourself:

```bash
systemctl --user enable --now persona-deploy-doctor.timer
```

On drift, the service logs to the journal and publishes a `wm.persona.drift`
bus event via `agorabus` (degrades to a warning if `agorabus` is absent).

```bash
# Check timer status
systemctl --user status persona-deploy-doctor.timer

# View last run output
journalctl --user -u persona-deploy-doctor.service -e

# Run a one-shot check now
systemctl --user start persona-deploy-doctor.service
```

## Testing

```bash
bash tests/run.sh
```

All tests run against fixture TOML files in `tests/fixtures/` — no live
config is touched, no network is used, all temp files go in `$TMPDIR`.

## Dependencies

- `bash` (4+), `python3` (3.11+ with `tomllib`)
- `agorabus` CLI (optional — degrades gracefully if absent)
- `wmd` is **not** required for the core health checks (TOML parsing uses Python)

## Files

| File | Purpose |
|------|---------|
| `doctor.sh` | Health checker — run directly or via systemd |
| `expected.example.toml` | Documents the expected-state file shape |
| `persona-deploy-doctor.service` | Systemd user service unit |
| `persona-deploy-doctor.timer` | Systemd user timer (daily) |
| `install.sh` | Installs units, prints enable command |
| `tests/run.sh` | Test suite (all checks green, no network) |
| `tests/fixtures/` | TOML fixtures for each failure mode |
