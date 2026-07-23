# Pi Agent Instructions

## Scheduled subagents

Pi subagent schedules are session-scoped. They stop when the parent Pi process exits and resume only with the same session. Do not use a one-shot scheduled agent containing a long sleep loop. Prefer interval schedules, and clearly warn that Pi must remain running.
