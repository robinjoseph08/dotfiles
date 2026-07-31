---
name: afk
description: Autonomously take a GitHub issue from ready-for-agent to a merged pull request.
disable-model-invocation: true
---

# AFK

Take one GitHub issue from the queue to the remote default branch while the user is away. Make routine decisions autonomously and prioritize quality over speed. Stop only for a genuine blocker with no safe, reasonable resolution.

## 1. Acquire the issue

Resolve the supplied issue number or URL against the current repository. Read the issue, its comments, and its GitHub dependency state. Confirm it is open, actionable, and not blocked by an open dependency.

Claim it by removing `ready-for-agent` when present and adding `in-progress`. Verify the resulting labels before changing code.

Completion criterion: the correct issue is understood, unblocked, and visibly claimed.

## 2. Implement it

Work on a non-default feature branch and preserve unrelated work. Read and follow [`../implement/SKILL.md`](../implement/SKILL.md), using the full issue and comments as the specification.

Follow the implementation through its code-review checkpoint. Resolve every valid finding, rerun the relevant checks after the final changes, and commit the finished work according to repository conventions.

Completion criterion: the issue is implemented, reviewed, committed, and passing the appropriate local checks.

## 3. Ship it

Read and follow [`../ship-it/SKILL.md`](../ship-it/SKILL.md). Give it the issue URL and implementation evidence so the pull request closes the issue and accurately reports what changed and how it was tested.

Stay with the workflow while CI runs. Let the ship-it skill handle repairs, conflicts, review of substantive follow-up changes, and squash merge.

Completion criterion: the pull request is verified as merged into the remote default branch, or ship-it has identified a genuine blocker requiring user input.

## 4. Finish

Verify the issue closed through the merged pull request. Remove the `in-progress` label after closure while preserving unrelated labels.

Report:

- Issue implemented
- Pull request URL and merge status
- Checks and review outcome
- Any blocker or follow-up

AFK is complete only when the pull request is merged and the issue is closed. If blocked, leave the repository and issue in a recoverable state and report exactly what is needed.
