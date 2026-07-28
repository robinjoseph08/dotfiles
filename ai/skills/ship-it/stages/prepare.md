# Ship-it stage: prepare

Perform only branch preparation. Do not review, push, or create a PR.

## Inputs

The coordinator prompt supplies the absolute working directory, checkpoint path, expected `HEAD`, mode, and autonomy. Read the checkpoint, repository instructions, and actual Git state before acting.

## Work

1. Verify the checkpoint belongs to this working directory and the expected `HEAD` still matches. Reconcile any stale recorded SHA before changing files. If `In-flight base refresh` exists, inspect the recorded old base/head, observed new base, expected remote SHA, and actual Git rebase state before any new fetch or mutation. Continue or complete that same refresh; never allocate a second refresh or discard an interrupted rebase.
2. Stop on detached HEAD.
3. If currently on the remote default branch, create a short descriptive feature branch. If already on a feature branch, retain it.
4. Inspect staged, unstaged, and untracked files. Stage intended files explicitly, never with a blanket command that could capture secrets or artifacts. In interactive mode, return `needs-input` for suspicious unrelated files. In autonomous mode, leave unrelated files untouched and stop if intended ownership cannot be determined safely.
5. Commit intended uncommitted work using repository commit conventions. Do not bypass hooks.
6. Fetch the remote default branch. Before rebasing a branch that already exists remotely, determine whether the rebase will require a force-push. A force-with-lease push is standing-authorized for any branch other than the remote default branch in both interactive and autonomous mode. Fetch the remote branch and determine its exact old remote SHA; no separate user confirmation is required. Never rewrite or force-push the remote default branch. Before rebasing, atomically record `In-flight base refresh` with the old base/head, observed new base, exact expected old remote SHA, clean-worktree proof, and operation state `starting`. This is the recovery boundary. Then rebase the feature branch onto the recorded new base if behind, updating the in-flight operation state after conflicts or successful completion.
7. Resolve conflicts only when the correct result is supported by the spec and surrounding code. Otherwise record a blocker. Any conflict resolution makes the patch-equivalent refresh path ineligible.
8. Verify the worktree is clean and a branch diff exists against the fetched default branch.
9. Record branch, base SHA, prepared `HEAD`, remote-branch state, the exact expected old remote SHA for any later force-with-lease push, and preparation history in the checkpoint. Keep `In-flight base refresh` until the review-path transition in step 10 is durable.
10. Choose the review path, then clear `In-flight base refresh` only in the same atomic checkpoint update that records the new prepared head and next stage:
   - **Patch-equivalent integration refresh:** eligible only when the prior review converged, the rebase was conflict-free, and `git range-diff <old-base>...<old-head> <new-base>...<new-head>` proves every feature commit patch-equivalent. Preserve the complete finding ledger, adjudications, verified fixes, and prior review history. Record old/new base and head SHAs plus bounded range-diff evidence. Set `Reviewed HEAD: pending`, invalidate final-gate evidence tied to the old head, and set `Stage: integration-review`. Do not rerun preflight or clear findings and attempt history.
   - **Full review invalidation:** required for initial preparation, non-converged prior review, conflicts, changed or ambiguous range-diff output, or a preparation reached from a failed-attempt base check. Use review cycle 1 initially; otherwise increment it and archive earlier ledgers rather than deleting them. Archive old/new base and head identities, bounded conflict resolutions and range-diff classification, unresolved findings, attempt evidence, successful commits, dispositions, verified fixes, and prior convergence with the old cycle. Clear only active attempt counters and pending findings because their evidence belongs to the invalidated diff; do not mark them fixed or invalid and do not erase their history. Set `Reviewed HEAD: pending`, reset final-gate evidence, and set `Stage: preflight-review`.

If there is no diff, record whether an existing PR exists. When none exists, atomically set `Outcome: nothing-to-ship`, `Status: complete`, and `Stage: complete`; do not claim PR publication. When a PR exists, verify its exact head branch, head SHA, body containing the checkpoint's exact required closing directive, nonempty URL, and an acceptable state of open or merged before recording `Outcome: complete-with-pr`. A closed unmerged PR never satisfies completion.

## Checkpoint safety

Write the checkpoint atomically. Do not store patch content, full command output, credentials, or expanded environment values.

## Return

```text
STATUS: prepared | complete | needs-input | blocked
HEAD: <sha>
BRANCH: <name>
BASE_SHA: <sha>
NEXT_STAGE: prepare | preflight-review | integration-review | complete | blocked
SUMMARY: <bounded factual summary>
BLOCKER: <only when applicable>
```
