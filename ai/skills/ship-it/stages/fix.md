# Ship-it stage: adjudicate and fix

Adjudicate a bounded batch of review findings and apply worthwhile fixes. Do not review your own work, push, create a PR, or post PR comments.

## Inputs and limits

The coordinator prompt must name the exact pending finding keys and summarize each. Verify those keys against the checkpoint and process at most three per invocation. If `Stage: preflight-fix` has no pending findings because both review axes were clean, perform only the preflight-to-normal transition below. Otherwise, if the prompt does not identify concrete findings, return a blocker rather than guessing.

Read repository instructions, the relevant code, the pinned diff, and the finding evidence. Verify checkpoint and actual `HEAD` before changing files. Before the first mutation, atomically record the selected keys under `In-flight fix` with the starting SHA. This is the recovery boundary if the stage stops.

A stage invocation may record at most one failed implementation attempt for a finding. If the checkpoint already records one failed attempt, this invocation is the fresh second attempt. Never make both attempts in one agent context.

## Adjudication

For each selected finding, record a concrete decision:

- **Fixed**: factually valid, passes the value bar, and is corrected in this batch.
- **Not fixed / Cosmetic**: factually valid but does not improve runtime behavior, regression detection, or factual user-facing accuracy.
- **Invalid**: factually wrong or inapplicable, with evidence.
- **Blocked**: valid and worthwhile but cannot be resolved safely. When the configured harness cannot expose a required deterministic proof and production changes, cache manipulation, sleeps, retries, or weaker assertions would not create valid evidence, use blocker kind `evidence-unavailable` and record a stable gate/check/environment capability fingerprint, exact evidence, bounded approaches ruled out, and continuation state. This consumes no failed implementation attempt.

Reclassify severity when needed and explain why. For normal findings, assign the next stable final-severity ID (`C1`, `I1`, `M1`, or `N1`) while preserving the round key. Preflight findings keep their Standards or Spec key and outcome.

A finding passes the value bar only when its fix:

1. improves runtime behavior,
2. adds or tightens a test against a plausible regression, or
3. corrects factually wrong user-facing text, docs, or comments.

Critical and important findings pass by definition unless reclassified with a reason. Do not dismiss findings merely because they are inconvenient.

## Fix work

1. In recovery mode, first inspect any dirty diff or commit after the recorded starting SHA and reconcile each in-flight key. Preserve pending status until its implementation and checks are verified.
2. Apply selected findings sequentially. Exercise new error and cancellation paths and sweep for collateral stale text or sibling contract drift caused by each fix.
3. If a finding intentionally changes behavior that an existing test asserts, diagnose that assertion before treating it as a regression. Verify the corrected contract from the spec, documented interface, and surrounding behavior. Then update the stale expectation and add or tighten coverage for the corrected behavior. A red assertion for behavior the finding intentionally replaces is not by itself a failed implementation attempt.
4. After each candidate fix, run targeted checks for the affected behavior. After the selected batch is stable, run the checkpoint's normal full check. Do not run the CI-equivalent suite.
5. Diagnose every check failure. Fix failures caused by the candidate and rerun the affected checks. If infrastructure is unavailable or the starting tree fails independently, record a blocker with evidence instead of consuming a finding attempt.
6. If a finding still cannot reach a coherent, passing implementation after honest diagnosis:
   - Revert only that finding's uncommitted changes. Preserve correct earlier fixes and unrelated state.
   - Increment its failed-attempt count exactly once, retain it as pending, and record the attempted approach plus bounded failure evidence.
   - Do not begin another selected finding and do not make another attempt in this invocation.
   - If this was its first failed attempt, return `retry-needed` so the coordinator launches a fresh fix-stage agent.
   - If this was its second failed attempt, return `retry-exhausted` so the coordinator checks whether the remote default branch advanced before deciding whether the Run is blocked.
7. Commit successful fixes from the batch locally using repository conventions when uncommitted changes remain. Do not push.
8. Update the checkpoint with outcomes, validation results, commit SHA, remaining pending keys, failed-attempt counts, and whether the batch changed runtime, tests, or prose only. Clear `In-flight fix` only after this state is durable.

## Transition

### After a failed implementation attempt

- After the first failed attempt, keep the current fix stage and active review cycle. Return `retry-needed`; the coordinator verifies clean state and fetches the remote default branch. An advanced base routes to `prepare`; a current base gets a fresh second-attempt agent.
- After the second failed attempt, keep the current fix stage and active review cycle. Return `retry-exhausted`; do not set `Status: blocked` or `Stage: blocked`. The coordinator fetches the remote default branch again. An advanced base routes to `prepare`; only an unchanged base turns the unresolved finding into a blocker.
- Preserve successful commits and every finding disposition from the same batch through either transition.

### From preflight-fix

- If preflight keys remain, keep `Stage: preflight-fix`.
- If none remain and no blockers exist, set `Stage: normal-review`, `Round: 1`, and clear normal convergence state.

### From normal-fix

- If current-round keys remain, keep `Stage: normal-fix`.
- If none remain and any worthwhile fix was committed during the round, increment the round and set `Stage: normal-review`. Mark prose-only scope only when every fix in the round touched prose.
- If none remain and the round produced no worthwhile fixes, set `Reviewed HEAD` to current `HEAD`, record convergence, and set `Stage: publish`.

Any fix commit requires a fresh later reviewer before publication. Never mark the current fixed `HEAD` reviewed yourself.

## Checkpoint safety

Persist bounded findings and check summaries, not full logs. Write atomically. If interrupted after a commit, ensure the next coordinator can see the commit SHA and route to fresh review.

## Return

```text
STATUS: fixed | adjudicated | retry-needed | retry-exhausted | blocked
PROCESSED: <finding keys>
OUTCOMES: <key=outcome summary>
ATTEMPTS: <key=failed attempts in current review cycle, or none>
COMMIT: <sha or none>
CHECKS: <targeted and full-check summary>
REMAINING: <keys or none>
NEXT_STAGE: preflight-fix | normal-review | normal-fix | publish | coordinator-base-check | blocked
BLOCKER_KIND: <evidence-unavailable | other, only when blocked>
BLOCKER_FINGERPRINT: <stable bounded fingerprint, only when blocked>
BLOCKER: <only when applicable>
```
