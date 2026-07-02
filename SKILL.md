---
name: babysit
description: Watch an idle Claude Code session for a rate-limit recovery moment and nudge it to resume when the window clears. Use when leaving an agent running unattended overnight or during meetings.
version: 0.2.1
---

# /babysit — Rate-limit recovery watcher

You are executing the `/babysit` skill. This watches a Claude Code session for the rate-limit-cleared-but-still-stuck state and sends a one-shot nudge prompt when conditions are right.

## Parse Input

The user's input is: `$ARGUMENTS`

**Parsing rules:**
- If empty, `--help`, or `help`: show the **Usage** section below and STOP — do not create any cron jobs.
- If a duration suffix is present (e.g. `1h`, `30m`, `overnight`): parse same shape as `/coffee`. Default duration: 6 hours.
- Optional: an explicit session id can be passed (UUID shape, e.g. `babysit be0b2b48-...`). If absent, watch THIS session (captured per Step 1).
- Minimum tick interval: 3 minutes. Maximum: 15 minutes. Default: 5 minutes.

## Usage (show this if no args or --help)

```
/babysit [duration] [session_id]

Watch an idle agent for rate-limit recovery and nudge it to resume.

Duration: how long to keep watching (default: 6h, max: overnight)
Session:  which session to watch (default: this one)

Examples:
  /babysit                    — watch this session for 6h
  /babysit overnight          — watch until 8 AM local
  /babysit 4h                 — watch for 4 hours
  /babysit overnight be0b2b48 — watch a sibling session overnight

How it works:
  Every 5 minutes, checks three things:
   1. Was the watched session's most recent traffic blocked by rate limits?
   2. Has the account-level quota window since cleared (status: allowed)?
   3. Has the session been quiet (no fresh tool calls) for 5+ minutes?

  If all three: sends a one-shot nudge prompt into the watched session via
  `claude -p --session <sid>`. Otherwise: silently holds.

  The nudge text explicitly says "if you stopped for any other reason,
  ignore this" — protects against false-positive nudges when the agent
  stopped for non-rate-limit reasons (waiting on user, etc.).

  Every tick writes a heartbeat to ~/.claude/babysit/<sid>.state so you
  can inspect watcher state mid-run:
    cat ~/.claude/babysit/<watched-sid>.state

  Auto-stops after the chosen duration AND deletes its own recurring cron
  so no zombie job is left running. Use /unbabysit to cancel sooner, or
  ask Claude to run CronList and delete the babysit job by id.
```

If showing usage, STOP HERE. Do not proceed to the steps below.

---

## Step 1: Capture session id to watch

Parse the user's `$ARGUMENTS`. If it contains a UUID-shape token (regex `[a-f0-9-]{20,}`), use that token as `<watched_sid>`.

Otherwise default to THIS session, using `/coffee`'s capture pattern:

```bash
watched_sid=$(python3 -c "
import os, glob
try:
    files = glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl'))
    if files:
        newest = max(files, key=os.path.getmtime)
        print(os.path.basename(newest)[:-len('.jsonl')])
except (OSError, ValueError):
    pass
" 2>/dev/null)
[ -z "$watched_sid" ] && watched_sid=$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl 2>/dev/null)
```

Embed `<watched_sid>` literally in the recurring cron prompt below.

## Step 2: Compute end time

From the duration argument, compute the absolute UTC datetime when the babysit should auto-stop. Use `date -u -d "+<N> minutes"` and capture as ISO timestamp. Embed literally in the cron prompt.

## Step 3: Prepare the state directory

Ensure `~/.claude/babysit/` exists (`mkdir -p ~/.claude/babysit`). This holds per-session heartbeat state files.

## Step 4: Arm the watcher (CronCreate)

Use `*/5 * * * *` (or chosen interval) as the cron expression. Pass the prompt below as the `prompt` argument. Mark as recurring (default). **Capture the returned cron id** — you will need it in Step 5.

The prompt the watcher fires every tick:

```
Babysit check for session <watched_sid>.
End-of-watch: <end_iso>. Cron id (self): <babysit_cron_id>.

Every path below writes ~/.claude/babysit/<watched_sid>.state as a
last-tick heartbeat before responding. Format:

  ts=<ISO>
  outcome=<outcome-tag>
  detail=<short-string>

Then respond with the short outcome line.

If the current UTC time is past end-of-watch, do the following in order:
  1. Write heartbeat with outcome=auto_stop, detail="end-of-watch reached"
  2. Call CronDelete with id=<babysit_cron_id> to disarm this watcher.
  3. Respond with: "Babysit ended (auto-stop). Cron deleted."
  4. Stop.

Otherwise evaluate these three conditions in order. The data source is
the per-session quota-status file written by cache-fix's cache-telemetry
extension. Do NOT filter usage.jsonl by sid — usage.jsonl's `sid` field
is a proxy-process ID shared across all CC sessions on the host, not a
per-CC-session identifier.

1. **Account-level status**. Read `~/.claude/quota-status/account.json`
   and check `status` and `overage_status`. Both must be `"allowed"`. If
   either is `"denied"` (rate limit still in effect):
   - Write heartbeat with outcome=holding_denied, detail="status=<X> overage=<Y>"
   - Respond with: `Babysit: window not cleared (status=<X>, overage=<Y>).`
   - Stop.

2. **Watched session activity gap**. Read
   `~/.claude/quota-status/sessions/<watched_sid>.json` (cache-fix
   v3.5.0+). If the file doesn't exist, fall back to legacy
   `~/.claude/quota-status.json` (cache-fix v3.4.x and earlier / preload
   mode). Extract the top-level `timestamp` field — this is the
   wall-clock time of the watched session's most recent proxy-handled
   request. Compute the gap in minutes between that timestamp and now.
   - If the gap is **less than 5 minutes**, the session is still active.
     - Write heartbeat with outcome=holding_active, detail="last request <N>m ago"
     - Respond with: `Babysit: session still active (last request <N>m ago).`
     - Stop.
   - If the gap is between **5 and 360 minutes** AND condition 1 passes,
     the session is quiet AND the rate-limit window is clear. **This is
     the trigger state.** Proceed to condition 3.
   - If the gap exceeds 360 minutes (6h), the session has been idle long
     past any plausible rate-limit recovery window — likely abandoned,
     restarted under a different sid, or never resumed.
     - Write heartbeat with outcome=abandoned, detail="idle <N>m"
     - Call CronDelete with id=<babysit_cron_id> to disarm this watcher.
     - Respond with: `Babysit: session inactive >6h, likely abandoned. Cron deleted.`
     - Stop.

3. **Account-status recent transition**. Read the account.json file's
   mtime via filesystem stat. If `status == "allowed"` AND the file was
   modified within the last 30 minutes AND condition 2 indicated a 5+
   minute gap, this is a strong signal that the rate-limit window
   recently cleared and the watched session has not yet noticed. Proceed
   to send the nudge. If account.json hasn't been touched recently (no
   recent state change):
   - Write heartbeat with outcome=holding_no_transition, detail="no recent status change"
   - Respond with: `Babysit: no recent rate-limit transition detected — nothing to nudge.`
   - Stop.

4. **Send the nudge into the watched session** (Bug #3 fix: real
   delivery via `claude -p --session`). Compose the nudge text:

   ```
   Babysit notice: the rate limit window appears to have cleared (Q5h
   status: allowed) and this session has been quiet for <N> minutes. If
   you were holding because of rate limiting, you can resume now. If you
   stopped for any other reason — waiting on user input, holding before a
   destructive action, intentionally idle — please ignore this nudge and
   stay where you are.
   ```

   Then shell out to feed it into the watched session:

   ```bash
   claude -p --session <watched_sid> --output-format json <<< "$NUDGE_TEXT"
   ```

   Capture the exit code and any error output.

   - On success: write heartbeat with outcome=nudge_sent, detail="quiet <N>m, delivery ok"
   - On failure: write heartbeat with outcome=nudge_failed, detail="<short error>"

   After the nudge fires (success or failure), disarm the watcher:
   - Call CronDelete with id=<babysit_cron_id>.

   Respond to the user (you) with either:
   `Babysit: nudge sent to <watched_sid> (window cleared, quiet <N>m). Cron deleted.`
   or:
   `Babysit: nudge delivery FAILED for <watched_sid>. See heartbeat file. Cron deleted.`
```

## Step 5: Confirm to the user

After CronCreate succeeds, echo:

```
Babysit armed for session <watched_sid>
  Cron id:    <babysit_cron_id>
  Tick:       every 5 min
  Auto-stop:  <end_iso>
  Heartbeat:  ~/.claude/babysit/<watched_sid>.state
  Will nudge once if: rate limit clears + session quiet 5+ min

The watcher will self-disarm on auto-stop, nudge delivery, or abandoned
detection. Use /unbabysit to cancel sooner, or ask me to CronDelete
<babysit_cron_id>.
```

Then STOP. Do not run additional checks.

---

## Design notes (not part of skill execution)

### What v0.2 changed vs v0.1

- **Bug #3 (nudge delivery)**: fixed. The tick prompt now shells out to `claude -p --session <watched_sid>` to deliver the nudge into the actual watched session, not just into the babysitter's context. Success/failure recorded to heartbeat.
- **Bug #6 (auto-stop self-disarm)**: fixed. Every terminal branch (auto-stop, abandoned, nudge sent, nudge failed) calls `CronDelete` on the captured babysit cron id. No zombie crons left running.
- **Bug #4 (observability)**: fixed. Every tick writes `~/.claude/babysit/<sid>.state` with ts, outcome tag, and detail string. A user running `/babysit overnight` can `cat` that file at any time and see whether the watcher is holding, why, and what state the last tick observed.

### Known limits of v0.2

- **Session-scoped only**: dies when the invoking CC session closes. The cron itself is in-CC (CronCreate), not systemd. A future v1.0 would install a systemd-user timer that calls `claude -p` externally.
- **Single-session**: invoke once per agent to watch. Multi-agent watching would need one invocation per target.
- **One-shot nudge only**: after the first nudge fires (success or failure), the watcher disarms. If the agent ignores the nudge and stays stuck, no further intervention. See `docs/open-questions.md` for the backoff-vs-one-shot design tension.
- **No 5h-reset awareness**: doesn't read `resets_at` from `account.json` to anticipate when the window will clear. Ticks at fixed intervals regardless.
- **Requires [cache-fix proxy](https://github.com/cnighswonger/claude-code-cache-fix)** — hard dependency, not optional. All three condition evaluations read files that cache-fix writes:
  - `~/.claude/quota-status/account.json` (v3.5.0+) — account-level status.
  - `~/.claude/quota-status/sessions/<sid>.json` (v3.5.0+) — per-session activity timestamp.
  - `~/.claude/quota-status.json` (v3.4.x / preload mode) — legacy single-file fallback, invoking session only.

  Without cache-fix running, none of these files exist and the skill has no source for the conditions it evaluates. Install cache-fix first.
