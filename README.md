# babysit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](https://opensource.org/licenses/MIT) [![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://github.com/anthropics/claude-code)

A [Claude Code](https://github.com/anthropics/claude-code) skill that watches an idle agent for a rate-limit recovery moment and nudges it to resume when the window clears.

## The problem

When Claude Code hits a Q5h or Q7d rate limit mid-task, the session stops. When the window clears — often 5 hours later, sometimes overnight — the session doesn't automatically resume. If you're not watching, the agent sits idle until you notice.

For long-running tasks (overnight sweeps, extended reviews, code migrations), this can waste hours of wall-clock time and leave work sitting incomplete right at the moment the account is unblocked.

## The solution

`/babysit overnight` schedules a watcher that ticks every 5 minutes and checks three conditions:

1. Is the account-level rate-limit window now clear (`status: allowed`)?
2. Has the watched session been quiet for 5+ minutes (no fresh proxy traffic)?
3. Did the account status file transition recently (last 30 minutes)?

When all three align, `/babysit` fires a one-shot nudge into the watched session via `claude -p --session <sid>`, telling the agent it can resume. The nudge text explicitly says *"if you stopped for any other reason, ignore this"* — so agents that are legitimately waiting for user input aren't spuriously restarted.

The watcher self-disarms on: nudge delivery, end-of-watch timeout, or abandoned-session detection (idle >6h).

## Installation

**One-liner:**

```bash
mkdir -p ~/.claude/skills/babysit && curl -fsSL https://raw.githubusercontent.com/vsits/babysit/main/SKILL.md -o ~/.claude/skills/babysit/SKILL.md
```

**Or clone and install:**

```bash
git clone https://github.com/vsits/babysit.git
cd babysit
bash install.sh
```

Restart Claude Code after installing to pick up the new skill.

## Requirements

- **Claude Code** — this is a Claude Code skill.
- **cache-fix proxy (recommended)** — the per-session activity signal comes from `~/.claude/quota-status/sessions/<sid>.json`, written by [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) v3.5.0+. Without it, the fallback path reads `~/.claude/quota-status.json` (single-session legacy), which is usable for the current session but not for sibling sessions.

## Usage

```
/babysit [duration] [session_id]
```

| Command | Duration | Description |
|---------|----------|-------------|
| `/babysit` | 6h | Default watch window |
| `/babysit 2h` | 2 hours | Short watch |
| `/babysit overnight` | Until 8 AM | Overnight watch |
| `/babysit overnight <uuid>` | Until 8 AM | Watch a sibling session by session id |

When invoked, the skill:

1. Captures the target session id (this session by default, or an explicit UUID).
2. Computes an end-of-watch UTC timestamp from the duration.
3. Ensures `~/.claude/babysit/` exists for heartbeat state.
4. Arms a recurring cron (`*/5 * * * *`) that runs the check-and-nudge logic every 5 minutes.
5. Prints the cron id and heartbeat file path so you can inspect state mid-watch.

## Observability

Every tick writes a heartbeat file at `~/.claude/babysit/<sid>.state`:

```
ts=2026-07-02T21:55:00Z
outcome=holding_denied
detail=status=denied overage=denied
```

Outcomes you may see:

- `holding_denied` — rate-limit window still in effect, waiting.
- `holding_active` — the watched session had fresh traffic within 5 min, no nudge needed.
- `holding_no_transition` — window is clear but account.json hasn't been touched recently, so no recent transition to nudge on.
- `nudge_sent` — the nudge was delivered into the watched session. Watcher disarms.
- `nudge_failed` — nudge delivery to the watched session failed. Watcher disarms; see detail string.
- `abandoned` — the watched session has been idle >6h. Watcher disarms.
- `auto_stop` — end-of-watch reached. Watcher disarms.

`cat ~/.claude/babysit/<sid>.state` at any point gives you the last tick's state without needing to inspect cron output.

## What it does NOT do

- Survive session death. The cron is a Claude Code in-session `CronCreate`, so if the babysitting session closes, the cron dies with it. Overnight resilience needs the invoking session to stay alive.
- Watch multiple sessions in one invocation. One `/babysit` call per target session.
- Predict 5h reset boundaries. Ticks at fixed intervals regardless of when the window is expected to clear.
- Handle anything other than rate-limit stalls. If your session is stuck for a different reason (compaction error, thinking-block wedge, etc.), see [claude-code-restore-history](https://github.com/vsits/restore-claude-history-linux) or the [thinking-wedged-session playbook](https://github.com/vsits/babysit/blob/main/docs/related-playbooks.md) instead.

## Design notes

See [`docs/open-questions.md`](docs/open-questions.md) for the design questions we deliberately punted on for v0.2 — most notably: nudge backoff/re-nudge policy, systemd-user timer for cross-session survival, and 5h-reset-boundary awareness.

## Related tools

- [claude-code-coffee](https://github.com/cnighswonger/claude-code-coffee) — companion skill that keeps your prompt cache warm during breaks. Different problem, same shape.
- [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) — the proxy that writes the per-session telemetry `/babysit` reads.

## License

MIT. See [LICENSE](LICENSE).
