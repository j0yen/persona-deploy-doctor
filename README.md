# persona-deploy-doctor

Checks that a deployed Jocelyn elder-persona config hasn't drifted from the state it was installed in.

A persona is a config, and config rots. Once `persona-deploy-jocelyn` writes the elder persona into `brain.toml`, nothing stops it from drifting back — a stray edit drops `forbidden_terms`, a reset flips `redline` to `Off`, a fresh-box re-provision leaves `self_name` at the default `wintermute`. The failure is silent. Nobody notices until Jocelyn calls herself a computer. This checks for that, on a schedule, and tells you before she does.

## What it checks

Four assertions against `[persona]` in `brain.toml`:

1. `forbidden_terms` is non-empty.
2. `redline` is an active action — not `Off`, not absent.
3. `self_name` equals the expected warm name (default `Clara`), and is not the default `wintermute`.
4. `wake_word` equals an expected value — only when you pass `--expect-wake-word`.

## Run it

The doctor is a single bash script; no build step.

```bash
./doctor.sh --config ~/.config/wintermute/brain.toml --expect-self-name Clara
```

Healthy:

```
$ ./doctor.sh --expect-self-name Clara --config ~/.config/wintermute/brain.toml
OK  persona config is healthy (checked: ~/.config/wintermute/brain.toml)
$ echo $?
0
```

Drifted:

```
$ ./doctor.sh --expect-self-name Clara --config /tmp/broken.toml
DRIFT detected in /tmp/broken.toml (checked at 2026-06-13T12:00:00Z)

Failing checks:
  FAIL  redline: [persona].redline is 'off' — redline guard is not active
  FAIL  self_name: [persona].self_name is 'wintermute' — persona has not been renamed from the default

Run with --json for machine-readable output.
$ echo $?
1
```

The exit code is the contract:

| Code | Meaning |
|------|---------|
| `0` | all checks passed |
| `1` | drift detected — each failing check is named in the report |
| `2` | error — config missing, unreadable, or TOML that won't parse |

With no `--config`, the doctor looks in `~/.config/wintermute/brain.toml`, `~/wintermute/wintermute-brain/brain.toml`, and `~/.wintermute/brain.toml`, in that order.

## JSON output

```
$ ./doctor.sh --config /tmp/fixture.toml --expect-self-name Clara --json
{"healthy":true,"drift":[],"checked_at":"2026-06-13T12:00:00Z"}
```

On drift, `healthy` is `false` and `drift` carries the `check_name: reason` strings, one per failure. The same string set drives both the text and JSON paths, so the two never disagree.

## Options

```
--config <path>            Path to brain.toml (default: auto-detected)
--expect-self-name <name>  Assert self_name equals this value (default: Clara)
--expect-wake-word <word>  Assert wake_word equals this value (optional)
--expect-redline active    Assert redline is active (always checked; only 'active' is accepted)
--json                     Emit JSON instead of text
--help / --version
```

## Run it on a schedule

`install.sh` copies the systemd user units into place and reloads the daemon. It does not enable anything — it prints the command and leaves the decision to you.

```bash
bash install.sh
systemctl --user enable --now persona-deploy-doctor.timer
```

The timer fires daily (with up to 30 minutes of jitter) and runs the doctor as a oneshot service. Output goes to the journal:

```bash
systemctl --user status persona-deploy-doctor.timer
journalctl --user -u persona-deploy-doctor.service -e   # last run
systemctl --user start persona-deploy-doctor.service    # check now
```

## How it works

The doctor doesn't depend on `wmd` or cargo to read the config — it parses `brain.toml` with Python's `tomllib` (3.11+) and applies the four checks in bash. `redline` is read whether it's a bare string or a `{ action = ... }` table. That's the whole design: small, dependency-light, and safe to run against a live config because it only reads.

## Where it fits

Part of the Jocelyn elder-persona family on wintermute. `persona-deploy-jocelyn` installs the persona; this checks it stays installed; `persona-redline-eval` measures whether the redline actually holds at inference time. Deploy, watch for drift, prove enforcement.

## Testing

```bash
bash tests/run.sh
```

Every case runs against a fixture in `tests/fixtures/` — one per failure mode (empty terms, redline off as string and as table, wrong name) plus a healthy baseline. No live config is touched and no network is used.

## Dependencies

- `bash` 4+
- `python3` 3.11+ (for `tomllib`)

## Files

| File | Purpose |
|------|---------|
| `doctor.sh` | the health checker — run directly or via systemd |
| `expected.example.toml` | documents the shape of a healthy `[persona]` block |
| `persona-deploy-doctor.service` | systemd user service (oneshot) |
| `persona-deploy-doctor.timer` | systemd user timer (daily) |
| `install.sh` | installs the units, prints the enable command |
| `tests/run.sh`, `tests/fixtures/` | the test suite and its fixtures |
