# Related playbooks

`/babysit` handles one specific failure mode: rate-limit stalls. If your Claude Code session is stuck for a different reason, these are the tools to reach for instead.

## Thinking-block wedges

Symptom: session appears alive but every model call returns `400: messages.N.content.M.type: 'thinking' input blocks must be provided first`. Common after abrupt model swaps or interrupted compactions.

Diagnosis and heal: check for thinking-block state in the session's `.jsonl` transcript and edit under a fully-stopped process. See the `heal-thinking-wedged-session` playbook in [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) for the full procedure. Editing the transcript under a live session is wasted work — CC replays from in-memory, not from disk.

## Auto-compact failures

Symptom: session dies during compaction with `Error during compaction: ...`. Often model access issues, sometimes timeout.

Diagnosis: check `~/.claude.json` for the correct model ID. See the `diagnose-broken-auto-compact` playbook.

## Session data loss

Symptom: session `.jsonl` transcript is missing or truncated after a crash / disk pressure event.

Recovery: see [restore-claude-history-linux](https://github.com/vsits/restore-claude-history-linux) — Linux port of the CC transcript-recovery tool, ZFS/Btrfs/Timeshift snapshot backends.

## Cache-fix / warmer issues

Symptom: warmer cron not firing, prompt cache going cold across breaks, or unexpected cache misses.

See [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) and [claude-code-coffee](https://github.com/cnighswonger/claude-code-coffee).

## Cross-agent coordination

If you're running multiple Claude Code agents in parallel and need one to keep the others alive during rate limits, `/babysit` handles that — pass the sibling session's UUID as the second argument. Each `/babysit` invocation watches one target, so you'll want one invocation per target session.

The observability model uses per-session heartbeat files (`~/.claude/babysit/<sid>.state`), so you can `cat` any target's state without touching the invoking session.
