# Pi Agent Instructions

## Scheduled subagents

Pi subagent schedules are session-scoped. They stop when the parent Pi process exits and resume only with the same session. Do not use a one-shot scheduled agent containing a long sleep loop. Prefer interval schedules, and clearly warn that Pi must remain running.

## Blocking subagents

Treat any subagent whose result can affect a later irreversible or externally visible action as blocking. Examples include reviewers whose findings could change a push, merge, deployment, publication, issue closure, or destructive operation.

Launch independent blocking subagents as foreground Agent calls in one parallel tool batch. Do not set `run_in_background: true`. Do not proceed until every blocking result has returned and its findings have been addressed.

If a blocking subagent must run in the background, record every returned agent ID and call `get_subagent_result` with `wait: true` for every ID before the dependent action. Verify that the received result set exactly matches the launched set. Completion notifications are advisory and must never be used as a synchronization barrier.
