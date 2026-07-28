# Ship-it stage: repair final validation

Repair one diagnosed failure from either the local final CI-equivalent gate or a hosted CI run in ship-it repair mode. Do not push, create a PR, or declare the repair reviewed.

## Inputs

The coordinator prompt must include the failed command when known and a bounded failure summary from the checkpoint. In hosted CI repair mode, it also includes failing check names and the pushed PR-head SHA. Verify local `HEAD` matches that expected SHA and the failure still applies before editing. Read repository instructions and relevant code before editing.

## Work

Before any repository mutation, inspect `In-flight final repair`. If present, reconcile its starting SHA, dirty diff or later commit, failure fingerprint, and actual checks; preserve potentially valid work until verified and continue that same repair. Otherwise reproduce before editing, then atomically record `In-flight final repair` with the starting SHA, hosted or local failure fingerprint, failed command, and selected scope immediately before the first edit.

1. Reproduce with the narrowest targeted check available.
2. Diagnose the root cause. Do not respond to an unexplained rerun pass by widening timeouts, adding retries, or declaring success.
3. Classify non-code blockers before editing:
   - External infrastructure that cannot be addressed safely is blocked with a stable infrastructure kind and fingerprint.
   - A deterministic required proof that the configured harness cannot expose is `evidence-unavailable` when production changes, cache manipulation, sleeps, retries, or weaker assertions would not create valid evidence. Record the gate/check/environment capability fingerprint, exact required evidence, bounded approaches ruled out, and continuation state. Make no repository change, consume no ordinary repair round, atomically set `Status: blocked` and `Stage: blocked`, and stop unchanged automatic reruns until the capability or independently valid evidence method changes.
4. Fix an actual repository defect and add or tighten regression coverage when appropriate.
5. Run affected targeted checks followed by the repository's normal full check. Do not run the complete CI-equivalent suite in this stage.
6. Commit the repair locally using repository conventions.
7. Atomically record the bounded diagnosis, checks, and commit SHA in the checkpoint, then clear `In-flight final repair`. A dirty tree or unrecorded later commit keeps the in-flight boundary for a fresh recovery agent.
8. Because the final reviewed tree changed, clear convergence, increment the normal review round, and set `Stage: normal-review`. Stop as blocked if this would exceed six rounds.

If investigation proves the command report was stale and the tree did not change, record why and atomically clear any `In-flight final repair` without changing HEAD. For a local final-gate report, set `Stage: publish`. For a hosted CI report on an unchanged PR SHA that already has an exact-SHA passing local final gate, record a stable stale-check key from the SHA, workflow/check identity, failed command, and normalized failure signature; exclude run and attempt IDs so reruns retain the same incident identity. Clear any pending ordinary repair classification without incrementing it, set `Stage: hosted-rerun`, and return `stale`. Do not publish or push the same SHA again, and do not silently treat an unexplained flake as stale.

## Return

```text
STATUS: repaired | stale | blocked
DIAGNOSIS: <bounded root cause>
COMMIT: <sha or none>
CHECKS: <targeted and full-check summary>
NEXT_STAGE: normal-review | publish | hosted-rerun | blocked
BLOCKER_KIND: <evidence-unavailable | infrastructure | other, only when blocked>
BLOCKER_FINGERPRINT: <stable bounded fingerprint, only when blocked>
BLOCKER: <only when applicable>
```
