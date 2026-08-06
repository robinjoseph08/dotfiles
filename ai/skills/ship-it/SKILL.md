---
name: ship-it
description: Publish reviewed work as a pull request and shepherd it through CI, conflicts, and squash merge. Use when the user says "ship it," asks to open and merge a PR, or wants completed work carried through to the default branch.
---

# Ship It

Ship the current work through a merged pull request. Quality is more important than speed.

## Prepare

Read the repository instructions and inspect the branch, working tree, remotes, default branch, existing pull request, and relevant issue.

Confirm that the intended changes have been reviewed and that the appropriate local checks pass. If the work has not been reviewed, or it changed materially after review, use the code-review skill and resolve every valid finding before publishing.

Do not discard unrelated work. Put the intended changes on a feature branch and commit them if needed. If you're already on a non-default branch, you can use that. Never push directly to the default branch. Follow repository conventions for commits, branches, pull requests, and issue references.

## Publish

Bring the branch up to date with the remote default branch when needed, resolving conflicts carefully and rerunning affected checks. Push the reviewed commits and create or update the pull request with an accurate summary, test evidence, and issue-closing reference when applicable.

Enable automatic merge using the squash strategy. If automatic merge is unavailable, wait for all required gates and then squash merge through the hosting platform.

Verify hosted state rather than assuming a command succeeded. The pull request must point at the expected branch and commit.

## Shepherd the pull request

Stay with the pull request until it merges or reaches a genuine blocker that requires user input.

When CI fails, inspect the failing job and logs, diagnose the cause, fix the underlying issue, run the relevant local checks, commit, and push. Review substantive repairs before publishing them.

When the branch becomes conflicted, update it from the latest default branch, resolve the conflicts, rerun the relevant checks, and push the resolution. Review the result when conflict resolution changes behavior.

Do not bypass required checks, weaken tests, or make speculative changes just to get a green build. Distinguish failures caused by the change from external or flaky infrastructure, and rerun hosted checks only when there is evidence that a rerun is appropriate.

## Complete

Confirm that the pull request was squash-merged into the remote default branch. Report:

- Pull request URL
- Final merge status
- Checks run and their outcomes
- Any remaining blocker or follow-up

Do not report completion merely because the branch was pushed or the pull request was opened.
