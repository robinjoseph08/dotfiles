# Ship-it stage: review

These are coordinator instructions for exactly one read-only review stage. Do not delegate review orchestration to a stage agent, because ordinary subagents may not have access to the Agent tool. The coordinator launches reviewer agents directly and does not modify repository files, commit, push, or create a PR during this stage.

## Common rules

- Verify checkpoint working directory, expected stage, base SHA, and `HEAD` before review.
- Every reviewer is a newly spawned independent subagent. A reviewer never launches another agent.
- Reviewers receive the branch diff, repository standards or spec, base/head SHAs, and only the prior ledger needed for deduplication. Do not provide implementation transcripts, private reasoning, anticipated findings, or fix plans.
- Reviewers must not modify files or Git state, invoke fix agents, push, create GitHub reviews, or post PR comments.
- Spawn reviewers synchronously. Parallel reviewers must be launched in one parallel foreground call. Never end the coordinator turn waiting for background notifications.
- Persist reviewer results and the next stage in the checkpoint before routing another stage.

## Integration refresh review

When `Stage: integration-review`:

1. Verify the checkpoint records a converged old reviewed head, old/new base and head SHAs, a conflict-free rebase, and patch-equivalence evidence for every feature commit. Missing or ambiguous evidence blocks; it never silently transfers convergence.
2. Spawn one fresh integration reviewer. Give it the complete rebased diff, the upstream `old-base..new-base` range, the preserved finding ledger, and every previously verified fix. Require it to assess semantic interactions introduced by the new base and explicitly confirm that prior fixes still hold on the rebased head.
3. If every prior fix remains complete and no semantic interaction is found, record the integration verification, set `Reviewed HEAD` to the new head, preserve prior review convergence as transferred evidence, and set `Stage: publish`.
4. If a prior fix became incomplete, restore its existing key to Pending work. If a new semantic interaction exists, assign a new normal finding key. Set `Stage: normal-fix`; after fixes, use the ordinary fresh normal verification path. Preserve all prior history.
5. If the reviewer omits an explicit result for any prior fix or fails to examine either required diff range, discard the incomplete result and launch one fresh reviewer. Record the malformed attempt and block after two such attempts.

## Preflight review

When `Stage: preflight-review`:

1. Read the code-review skill completely.
2. Spawn fresh Standards and Spec reviewers synchronously and in parallel.
3. Standards reviews documented repository standards and the code-review skill's baseline design smells.
4. Spec reviews caller-supplied issue or PRD behavior. If autonomous and no spec exists, record `no spec available` without launching that reviewer. If interactive and no spec can be found, return `needs-input` without changing the stage.
5. Preserve both reports separately. Do not adjudicate or fix findings in this stage.
6. Give each raw finding a preflight key such as `S1` or `P1`, record its source and claimed severity, and add it to Pending work.
7. Set `Stage: preflight-fix`. If both axes are clean, Pending work is empty but the fix stage still records completion and advances.

## Normal review

When `Stage: normal-review`:

1. Refuse to run if the checkpoint has unresolved pending findings from an earlier round.
2. Stop as blocked before starting round 7. Six rounds is the workflow limit.
3. Round 1 launches three fresh reviewers synchronously and in parallel:
   - **Robustness**: ask what bad inputs, error paths, boundaries, or false success gates can produce incorrect runtime behavior.
   - **Test strength**: for each behavior, ask for a plausible regression that would pass the existing tests.
   - **Surface accuracy**: check user-facing text, docs, help, errors, and comments against actual behavior.
4. Rounds 2 and later launch one fresh verification reviewer. Give it the complete accumulated normal ledger plus every item marked Fixed since the preceding review. Require an explicit verification result for each fix. An absent or incomplete fix is reported under its existing finding key, not as a duplicate. Resolved, invalid, and cosmetic items are not repeated without new evidence.
5. Review the complete diff against the pinned base. Use a scoped prose review only when the checkpoint explicitly says the preceding fixes changed prose only.
6. Dedupe same-cause findings across reviewers. Give each new raw finding a round key such as `R2-F1`; leave its final stable severity ID pending adjudication.
7. Save every finding before any mutation stage begins.
8. If no new findings are reported and every required prior fix was explicitly verified, set `Reviewed HEAD` to current `HEAD`, record convergence, and set `Stage: publish`.
9. If an earlier fix is absent or incomplete, restore its existing key to Pending work and increment its failed-attempt count exactly once. Add genuinely new finding keys separately, set `Stage: normal-fix`, and return control to the coordinator's base-freshness decision before another fix attempt:
   - Count 1 returns `retry-needed`.
   - Count 2 returns `retry-exhausted`.
   - A count above 2 is invalid checkpoint state and blocks.
   - When multiple fixes are incomplete, record every affected count. `retry-exhausted` takes precedence if any finding reaches count 2; otherwise return `retry-needed`.
10. If the reviewer omits an explicit result for any required prior fix, treat the review as incomplete. Preserve `Stage: normal-review`, discard that review result, and launch a fresh reviewer. Record the malformed attempt and block after two such attempts rather than looping forever.
11. When pending keys exist but no prior fix was reported absent or incomplete, record that the round has not yet produced fixes and set `Stage: normal-fix` with ordinary `reviewed` status.

## Return

```text
STATUS: reviewed | clean | retry-needed | retry-exhausted | needs-input | blocked
REVIEW_KIND: preflight | normal | integration
ROUND: <number or n/a>
FINDING_KEYS: <comma-separated keys or none>
ATTEMPTS: <restored key=failed attempts in current review cycle, or none>
HEAD: <unchanged sha>
NEXT_STAGE: preflight-review | preflight-fix | normal-review | normal-fix | integration-review | publish | coordinator-base-check | blocked
SUMMARY: <bounded factual summary>
BLOCKER: <only when applicable>
```
