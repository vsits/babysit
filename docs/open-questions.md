# Open design questions

These are design decisions we deliberately punted on for v0.2.0. Each is a candidate for a future release; each has an issue on the repo tracking it.

## 1. Nudge backoff / re-nudge policy

**Current behavior:** one-shot. After the first nudge fires (success or failure), the watcher disarms. If the agent ignores the nudge and stays stuck, there's no further intervention.

**Tension:** one-shot is safer (no false-positive spam) but weaker (won't recover from a nudge that landed but was dismissed). A backoff policy — nudge, wait 10 min, nudge again if still quiet, then give up — trades false-positive risk for recovery robustness.

**Open question:** what's the right backoff shape? Fixed 10-min interval? Exponential? User-configurable via `--nudge-attempts N`? What's the ceiling before we conclude the agent is genuinely stuck for a non-rate-limit reason?

Filed as [#1](https://github.com/vsits/babysit/issues/1).

## 2. Systemd-user timer for cross-session survival

**Current behavior:** the cron is a Claude Code in-session `CronCreate`. If the babysitting session closes (crash, `/clear`, terminal window closed), the cron dies with it.

**Tension:** users who invoke `/babysit overnight` want it to keep watching even if their terminal disconnects. Requires either (a) a systemd-user timer that shells out to `claude -p` externally, or (b) a persistent daemon that reads the same state files.

**Open question:** is the added installation complexity (systemd-user unit file, timer file, ExecStart script) worth the survival guarantee? For which user population? Casual users probably don't need it; heavy overnight users probably do.

Filed as [#2](https://github.com/vsits/babysit/issues/2).

## 3. 5h-reset boundary awareness

**Current behavior:** fixed 5-minute tick interval regardless of when the Q5h window is expected to clear.

**Tension:** the account.json file contains a `resets_at` timestamp. A smarter watcher could sleep until 30 seconds before `resets_at`, wake up, check status, and back off if not cleared. Fewer ticks, tighter recovery latency.

**Open question:** worth the complexity? Every tick is cheap; the value of sleeping through them is minimal. Maybe more useful as a display-only feature: "next expected clear: 21:47 UTC" in the arming confirmation.

Filed as [#3](https://github.com/vsits/babysit/issues/3).

## 4. Test harness

**Current behavior:** no automated tests. All validation is manual smoke-testing.

**Tension:** the skill has state-dependent decision logic (three conditions across multiple files with timestamps and mtimes). A fixture-based test — synthetic `~/.claude/quota-status/` file trees, mocked `claude -p` invocations — would catch regressions on the condition-evaluation logic and the terminal-branch disarm calls.

**Open question:** what shape? `bash` + `bats`? Python + `pytest` with a fake filesystem? Something CI-friendly on GitHub Actions?

Filed as [#4](https://github.com/vsits/babysit/issues/4).
