# Ship-it stage: final validation and push

Perform only the guarded final gate and push. Do not modify repository files, fix failures, review code, or create the PR.

## Preconditions

Verify all of these against Git and the checkpoint:

- checkpoint stage is `publish`
- worktree is clean
- current `HEAD` equals `Reviewed HEAD`
- no unresolved worthwhile or pending findings exist
- review convergence was recorded for this exact `HEAD`

Fetch the remote default branch before validation. If its SHA differs from the pinned base, do not rebase or overwrite the pinned base here. Preserve the converged reviewed base/head and all review evidence as the candidate for patch-equivalence transfer, record the newly fetched base separately as `Observed advanced base`, set `Mode: integration-refresh` and `Stage: prepare`, and return `base-advanced`. Preparation alone decides whether to transfer review through integration verification or fully invalidate the cycle.

Inspect the remote feature branch and any existing PR. A remote already at local `HEAD` proves only that the commit was pushed, not that ship-it validated it. Skip the final gate only when the checkpoint also records a passing final gate for this exact SHA. If a non-default remote branch diverges in a way that requires force, use the standing force-with-lease authorization in both interactive and autonomous mode. Require the checkpoint's expected old remote SHA to match the freshly fetched remote branch, then use `--force-with-lease` against that exact SHA. Never force-push the remote default branch.

## Final gate

1. Unless the checkpoint already records a passing final gate for this exact SHA, run every command in the checkpoint's CI-equivalent suite in the foreground against the exact reviewed commit.
2. On failure, do not edit files. Save only the failed command, exit status, and bounded diagnostic summary. Set `Stage: final-repair` and return.
3. On success, record the validated SHA and commands.
4. Recheck that `HEAD` and the worktree are unchanged.
5. Fetch the remote default branch again. If it advanced during the suite, invalidate only the passing gate tied to the old base/head. Preserve the converged reviewed base/head and complete review ledger as patch-equivalence candidate evidence, record the new SHA separately as `Observed advanced base`, set `Mode: integration-refresh` and `Stage: prepare`, and return `base-advanced` without pushing. Do not overwrite the pinned old base or preempt preparation's review-path decision.
6. If the remote feature branch is not already at the validated SHA, push that exact SHA immediately with no intervening file changes. When rewriting a non-default branch, use force-with-lease against the checkpoint's exact expected old remote SHA as described above.
7. Verify the remote branch resolves to the validated SHA.
8. Record push success, including whether this was an initial or repair push, and set `Stage: pr`.

A later successful attempt may rerun the full final gate only after a repair and fresh review convergence. The ordinary successful path runs it once.

## Return

```text
STATUS: pushed | already-pushed | validation-failed | base-advanced | blocked
VALIDATED_HEAD: <sha or none>
FINAL_GATE: <pass or bounded failure>
REMOTE_HEAD: <sha or none>
NEXT_STAGE: pr | final-repair | prepare | blocked
BLOCKER: <only when applicable>
```
