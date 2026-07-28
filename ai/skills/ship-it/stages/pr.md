# Ship-it stage: PR upsert

Create or update the pull request for the already pushed, reviewed SHA. Do not modify code, rerun review, push, or post review comments.

## Preconditions

Verify:

- checkpoint stage is `pr`
- local `HEAD`, validated SHA, and remote feature branch SHA match
- the worktree is clean

If they do not match, record a blocker instead of publishing stale metadata.

Read the durable `PR verification attempts` before any GitHub mutation. A count of 2 blocks immediately without another lookup or increment; a count above 2 is invalid checkpoint state. This makes a crash after persisting the second failure safe to resume.

## Work

1. Find an existing PR by head branch before creating one.
2. Derive the final title from all branch commits and repository conventions. If the repository uses categorized squash titles, preserve that format.
3. Build a body containing:
   - any checkpoint PR body prefix, such as `Closes #123`, first
   - `## Summary` with one to three bullets describing final reviewed behavior
   - `## Test plan` with bullets listing meaningful verification
4. Create the PR if absent. Otherwise update title or body only when stale.
5. Never call `gh pr review`, post review comments, or add a general PR comment.
6. After create or update, perform a fresh authoritative lookup by the exact head branch. Require one PR with the expected head branch and pushed head SHA, an acceptable open or merged state, a nonempty canonical URL, and a body containing the checkpoint's exact required PR body prefix. For issue-backed work, verify the directive names the canonical issue identity: `Closes #N` only in the same repository, otherwise `Closes owner/repo#N`. Command success and printed output are not postcondition evidence.
7. If fresh verification fails, increment `PR verification attempts` exactly once, retain `Status: active` and `Stage: pr`, preserve every reviewed/validated/pushed SHA, record a bounded diagnostic, and return `retry-needed`. Do not record the unverified URL. A fresh stage may retry idempotently; two failed verification attempts block.
8. Record the verified PR number, URL, title, state, and final pushed SHA.
9. Build a bounded final-report draft from the checkpoint, including separate preflight axes, every normal finding and outcome, rounds, checks, push, and PR.
10. Atomically set `Outcome: complete-with-pr`, `Status: complete`, and `Stage: complete`. This transition is invalid without the verified PR postcondition above. Empty-diff work uses `Outcome: nothing-to-ship` in preparation and never reaches this stage.

## Return

```text
STATUS: complete | retry-needed | blocked
PR_URL: <url>
TITLE: <title>
PUSHED_SHA: <sha>
REVIEW_SUMMARY: <bounded consolidated summary>
BLOCKER: <only when applicable>
```
