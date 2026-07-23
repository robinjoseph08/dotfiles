---
name: afk
description: Autonomously implement a GitHub issue end-to-end while the user is away. Fetches the issue, delegates implementation through the implement skill, ships a PR with code review, and enables auto squash merge. Use when the user says /afk, "work on this while I'm gone", "implement this issue", or wants hands-off issue-to-PR delivery. Also use when no specific issue is given — it picks the oldest ready-for-agent ticket.
---

# AFK — Autonomous Issue-to-PR

Take a GitHub issue from spec to merged PR without human intervention.

## Coordinator pattern

The main session is a **coordinator**. The heavy, noisy work (reading lots of code, iterating on tests, applying review fixes) runs in **subagents** so it doesn't fill the main context window — long AFK runs would otherwise compact mid-flight and lose the thread.

What the main session does directly:
- Fetch and claim the issue (cheap `gh` calls)
- Discover the project's validation commands (cheap reads of CI config and task runner files)
- Spawn the implementation subagent and read back its summary
- Spawn the ship-it subagent and read back PR URL + review summary
- Enable auto-merge and write the final report

What the subagents do:
- **Implementation subagent**: follows the implement skill for the feature/fix, runs targeted checks and the project's full validation, then leaves the work uncommitted for ship-it
- **Ship-it subagent**: follows the ship-it skill end-to-end — commit, rebase, push, PR creation, the Standards/Spec preflight, and the full iterative code review + fix loop

Subagents share the main working tree — no worktree shuffle. They run serially, so no conflicts. Each one returns a tight structured summary; the main session uses those summaries to brief the next subagent and to write the final report.

## Input

- **With argument**: `/afk <issue-url-or-number>` — work on that specific issue
- **No argument**: pick the oldest open issue labeled `ready-for-agent`

## Step 1: Acquire the issue (main session)

**If an issue URL or number was provided**, fetch its body and all comments, then run the blocker check below before claiming it:

```bash
gh issue view <issue-url-or-number> --json number,title,body,comments,state,url
```

**If no argument**, find the oldest unblocked ready-for-agent issue:

1. Fetch candidate identities sorted by age:

   ```bash
   gh issue list --state open --label "ready-for-agent" --limit 1000 --json number,title,createdAt --jq 'sort_by(.createdAt)'
   ```

2. For each candidate, oldest first, fetch its full body/comments and run the same blocker check below.
3. Pick the first candidate that is not blocked. Silently skip blocked candidates; do not ask permission to override their dependencies because the user did not explicitly request them.

If no unblocked issues match, stop and tell the user there's nothing in the queue. Report how many issues were skipped and identify their open blockers.

### Determine whether an issue is blocked

Check both sources; an open dependency found in either source makes the issue blocked.

1. **GitHub's native dependency tracking.** List the issues the candidate is natively marked as blocked by:

   ```bash
   gh api \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     "repos/{owner}/{repo}/issues/<number>/dependencies/blocked_by" \
     --paginate \
     --jq '.[] | select(.state == "open") | {number, title, url: .html_url}'
   ```

   Use the candidate issue's owner and repository when an issue URL targets a repository other than the current one. Treat every returned open issue as an active blocker. If the dependency query fails, do not silently interpret the failure as "no dependencies"; retry with the correct repository/API access, then report the lookup failure if it remains unavailable.

2. **Explicit dependency statements in the issue body or comments.** Read the body and every comment in chronological order. Recognize clear statements such as `blocked by #123`, `depends on owner/repo#123`, or `waiting for <issue URL>`. Resolve each referenced issue and check its current state:

   ```bash
   # Same-repository number or a full issue URL
   gh issue view <number-or-url> --json state,title,url

   # Cross-repository owner/repo#123 reference
   gh issue view <number> --repo <owner/repo> --json state,title,url
   ```

   Treat the candidate as blocked when at least one explicitly named dependency is open. Do not infer a dependency from a bare issue mention, related-work link, checklist item, or vague sequencing language. For text-derived blockers only, a later explicit statement that the dependency was removed, resolved, or no longer blocks the work supersedes the older statement. Native dependencies remain blockers until removed in GitHub or closed.

### Handle an explicitly requested blocked issue

If the user explicitly selected an issue and the blocker check finds any open dependency, stop before claiming the issue or changing repository state. Name the open blockers and ask the user to confirm that they want AFK to work on the issue anyway. A direct issue request by itself is not permission to ignore its blockers.

If the same request already explicitly says to proceed despite blockers, or the user replies that they want to continue anyway, accept that override and continue normally. Do not ask again for the same known blockers; preserve the blocker details in the implementation brief so the subagent understands the dependency context.

Read the issue body and comments yourself enough to:
- Confirm you understand what's being asked
- Decide it's actionable (not a question, not under-specified to the point of being unworkable)

You don't need to deeply explore the code at this stage — that's the implementation subagent's job. You just need enough to write a good brief.

Then claim it:

```bash
gh issue edit <number> --remove-label "ready-for-agent" --add-label "in-progress"
```

Note: if the `in-progress` label doesn't exist, create it.

## Step 2: Delegate implementation to a subagent

Spawn a single implementation subagent. The subagent does all the code reading, test writing, and iteration in its own context. You receive a structured summary back.

Before writing the brief, identify the project's validation commands so the subagent doesn't guess. Check, in order: CI workflows (`.github/workflows/`), the project's CLAUDE.md and README, and the task runner config (Makefile, mise.toml, justfile, package.json scripts). The goal is the exact set of commands that must pass before a PR is mergeable (build, test, lint). Put those commands in both subagent briefs, including any quirks needed to match CI (for example a linter that must run at a specific version).

### Implementation subagent prompt template

Give the subagent everything it needs to work without coming back to you. Use the Agent tool with `subagent_type: "general-purpose"` and a prompt along these lines (fill in the angle-bracketed parts):

```
You are implementing GitHub issue #<N> in the <owner>/<repo> repository. The user is AFK; you are autonomous and must make all judgment calls yourself.

## Issue
Title: <title>
Body:
<full body>
Comments:
<comments, if any>
Dependency override:
<none, or the open blockers and the user's explicit instruction to proceed anyway>

## Working directory
<absolute path of the current repo / branch>

## How to work

1. Check the project's root CLAUDE.md and any relevant subdirectory CLAUDE.md files. Violations are review failures.

2. Read the implement skill at `~/.agents/skills/implement/SKILL.md` and follow its implementation and testing workflow. Treat the issue body, comments, and dependency override above as the spec. Apply these AFK-specific overrides:
   - Do not invoke code-review; the ship-it subagent owns the Standards/Spec preflight and iterative review and fix loop in step 3.
   - Do not commit; leave the completed changes uncommitted for the ship-it subagent.
   - Use the repository-specific targeted and full validation commands below.

3. After implementation, run the targeted subset of the validation commands for what you touched (fast feedback first):

<targeted check commands for this repo, per area touched>

4. Then run the full validation suite, matching what CI runs:

<full validation commands for this repo, including any quirks needed to match CI>

   Do not skip this. If it fails, fix and re-run until it passes; that is part of your job, not the coordinator's.

   You are a subagent: never end your turn to wait for a background task, because ending your turn kills the task and its completion notification never arrives. Run long commands (builds, E2E suites) in the foreground with a generous timeout, or block on a backgrounded task with TaskOutput (block=true) in the same turn.

5. Before returning, run this self-review pass over your own work:
   - **Error branches**: every error return and failure path you added has a test, or you can state why not.
   - **Stale text sweep**: search help text, error messages, README, and comments for claims your change invalidated (old tool names, old preconditions). Check that every message describing a condition matches the code's actual check (for example "X is not set" versus a check for non-empty).
   - **Sibling symmetry**: where two code paths share a contract (such as create and resume), every plumbing or regression test on one has a mirror on the other, or a stated reason it doesn't apply.
   - **Doc honesty**: comments and interface docs describe what the code does now, not the planned end state.

6. Do not commit, push, or create a PR. The coordinator handles git operations. Leave changes uncommitted in the working tree.

## When to stop and report a blocker instead of guessing

Stop and return a blocker if:
- The issue is genuinely ambiguous and there is no reasonable default
- A test is failing in a way you cannot diagnose after honest investigation
- A dependency or piece of infrastructure is broken in a way you cannot fix in scope

Do not ship something broken or invent functionality the issue does not call for.

## Return format

Return a single message structured exactly like this:

STATUS: success | blocked

SUMMARY:
<2-4 sentences on what you built and how>

FILES CHANGED:
- path/to/file.go — what changed and why
- path/to/other.tsx — what changed and why

BEHAVIORS TESTED:
- behavior 1 (test file:test name)
- behavior 2 (test file:test name)

CHECKS:
- <each validation command>: pass | fail | skipped (details)

NOTES FOR PR BODY:
<any specifics the coordinator should mention in the PR description: trade-offs, follow-ups, things reviewers should look at first>

BLOCKER (only if STATUS is blocked):
<what's blocking, what you tried, what input is needed>
```

When the subagent returns:
- If `STATUS: blocked` → report the blocker to the user, leave the issue in `in-progress` (or restore `ready-for-agent` if that's more appropriate), and stop.
- If `STATUS: success` → continue to step 3.

## Step 3: Ship and review (ship-it subagent)

Delegate the entire shipping and review workflow to a single subagent that follows the **ship-it skill**. This keeps afk in sync with ship-it — any improvements to ship-it's commit logic, PR formatting, or review loop automatically apply to AFK runs.

Spawn a subagent with `subagent_type: "general-purpose"`. The subagent reads the ship-it skill file and follows its full workflow (commit, rebase, push, PR creation, Standards/Spec preflight, iterative code review + fix loop).

### Prompt template for the ship-it subagent

```
You are shipping work for GitHub issue #<N> in the <owner>/<repo> repository. The user is AFK and no human is available. Make all judgment calls yourself. Do not ask questions.

## How to work

Read the ship-it skill file at ~/.claude/skills/ship-it/SKILL.md and follow its full workflow end-to-end. That skill defines how to commit, rebase, push, create the PR, run the Standards/Spec preflight, and run the iterative code review + fix loop.

Apply the following overrides to the ship-it workflow:

1. **PR body must reference the issue.** Add `Closes #<N>` as the first line of the PR body, before the `## Summary` section.

2. **Use this context for commit messages and the PR body** (from the implementation subagent):

SUMMARY:
<implementation subagent's SUMMARY>

BEHAVIORS TESTED:
<implementation subagent's BEHAVIORS TESTED>

NOTES FOR PR BODY:
<implementation subagent's NOTES FOR PR BODY>

3. Check root CLAUDE.md and any relevant subdirectory CLAUDE.md files. Violations are review failures.

4. **Validation commands for this repo** (matching CI): <full validation commands, including any quirks needed to match CI>. Run these after every fix round, per the ship-it skill.

5. **You are a subagent; never end your turn to wait for background work.** Ending your turn kills every background task you started (reviewer agents, E2E runs) and their completion notifications never arrive, stalling the whole run. Spawn reviewers synchronously (run_in_background: false; multiple synchronous Agent calls in one message still run concurrently) and run long commands in the foreground with a generous timeout. If you must background something, block on it with TaskOutput (block=true) in the same turn until it finishes. Only end your turn when you are returning the final report below.

## Return format

PR_URL: <url>

REVIEW_SUMMARY:
<the consolidated findings report from ship-it's final report — Standards/Spec preflight, iterative rounds, all findings, validation outcomes>
```

When the subagent returns:
- If it returns without the final report because it stopped to "wait" for background reviewers or a background E2E run, its background children are already dead (a subagent's background tasks are killed when its turn ends). Do not wait for them. Resume the same subagent via SendMessage, tell it explicitly that its background tasks were killed and will never notify, and instruct it to redo that work synchronously (reviewers with run_in_background: false, long commands in the foreground or blocked on with TaskOutput block=true) and to end its turn only with the final report. Check what already exists (commits, the PR) first and say so in the resume message so it doesn't recreate them.
- If it reports blockers it couldn't resolve (review findings it couldn't fix, rebase conflicts, push rejections), surface them to the user.
- Otherwise, extract the PR URL and review summary for the final report, then continue to step 4.

## Step 4: Merge the PR

First, try to enable auto squash merge:

```bash
gh pr merge --squash --auto
```

**If auto-merge is enabled**, do not consider the run finished yet. Watch the checks below until the PR merges or a failure needs attention. This is necessary because an Actions billing failure leaves auto-merge enabled forever even though no job can run.

**If auto-merge can't be enabled**, look at why:

- **The repository doesn't allow auto-merge** (the error mentions auto-merge is not allowed or not enabled for the repository, e.g. `enablePullRequestAutoMerge`). This is common and expected. Fall through to the watch-and-merge loop below rather than reporting a failure.
- **Any other reason** (required human approvals you can't satisfy, other branch protection you can't clear). Report it to the user and stop. Do not force-merge.

### Watch-and-merge loop

Babysit CI whether auto-merge was enabled or unavailable. Merge the moment it is safe. Cap ordinary CI failures at **3 fix rounds**. If CI is still red after that, stop and report to the user.

1. **Watch the checks** for the PR until they finish:

   ```bash
   gh pr checks --watch
   ```

   This blocks until every check on the latest commit completes, then exits 0 if all passed and non-zero if any failed. If it reports there are no checks at all, confirm the repository genuinely has no CI workflow for the PR before treating that as green; a newly pushed commit can have a short delay before its checks appear.

2. **If CI is green:**

   - If auto-merge is enabled, verify that GitHub completes the merge. If it remains open briefly after checks pass, inspect unmet requirements with `gh pr view` before deciding whether to wait or report a blocker.
   - If auto-merge is unavailable, merge directly:

     ```bash
     gh pr merge --squash
     ```

   If this merge is rejected because checks haven't finished yet (a race right after a push), go back to step 1 and watch again.

3. **If CI is red**, list the failing checks (cheap, keep it in the main context):

   ```bash
   gh pr checks
   ```

   Inspect the failed run before delegating a code fix. Use `gh run view <run-id> --log-failed` and, when no job log exists, inspect the run/check details through `gh run view` or `gh api`. Classify it as an Actions billing failure only when GitHub explicitly says the job was not started because of a billing/payment problem or an Actions spending limit. Do not infer billing from a generic startup failure, missing logs, a cancelled/skipped job, a runner outage, or another infrastructure error.

   - **Verified Actions billing failure:** use the billing fallback below.
   - **Any ordinary CI failure:** spawn a CI-fix subagent (template below) with the PR number and the names of the failing checks. It pulls the failure logs, fixes the cause, re-runs local validation, and pushes. When it returns:
     - `STATUS: fixed` → the push re-triggered CI. Go back to step 1 and watch the new run.
     - `STATUS: stuck` → report the blocker to the user and stop.

### Actions billing fallback

An explicit GitHub Actions billing failure means CI could not execute; it is not evidence that the change failed validation. In this one case, merge despite the stuck required checks, but only after all of these safeguards pass:

1. Confirm every failing or non-running required check is explained by the same explicit billing error. If any check reports a real test, build, lint, review, security, or policy failure, do not use this fallback; handle that failure normally.
2. Confirm the working tree is on the PR's exact latest commit. Compare `git rev-parse HEAD` with `gh pr view --json headRefOid --jq '.headRefOid'`, and require `git status --porcelain` to be empty. Fetch or check out the PR head first if they do not match.
3. On that exact commit, rerun the complete CI-equivalent validation suite discovered in step 2. A pass from before the latest push is insufficient. Every command must finish successfully; failed, skipped, unavailable, or unrun validation does not count as a pass.
4. If all local validation passes, administratively squash-merge the PR so the billing-blocked required checks cannot leave it stuck forever:

   ```bash
   gh pr merge --squash --admin
   ```

   This is the only case in this workflow that authorizes bypassing required checks. If GitHub refuses the administrative merge because the token lacks permission or because another non-CI requirement is unmet, report the blocker; do not weaken any other protection.
5. Verify the PR state is `MERGED` before continuing to the final report.

### CI-fix subagent prompt template

Spawn with `subagent_type: "general-purpose"`:

```
You are fixing failing CI for the PR that closes GitHub issue #<N> in <owner>/<repo>. The user is AFK; you are autonomous and must make all judgment calls yourself. Do not ask questions.

## Working directory
<absolute path of the repo / PR branch>

## Failing checks
<names of the failing checks from `gh pr checks`>

## How to work

1. Pull the failure logs for the failing checks so you know exactly what broke:

   gh pr checks            # map checks to their runs
   gh run view <run-id> --log-failed

2. Reproduce the failure locally where you can, using this repo's validation commands (matching CI): <full validation commands, including any quirks needed to match CI>.

3. Fix the root cause, not the symptom. If a test is legitimately failing, fix the code; only change the test if the test itself is wrong. For code changes, read the implement skill at `~/.agents/skills/implement/SKILL.md` and follow its implementation and testing workflow, treating the issue and CI failure as the spec. Do not invoke code-review here; the ship-it review has already run. Respect root and subdirectory CLAUDE.md files; violations are review failures.

4. Re-run the full validation suite locally until it passes. You are a subagent: never end your turn to wait for a background task (ending your turn kills it and its notification never arrives); run long commands in the foreground with a generous timeout, or block on a backgrounded task with TaskOutput (block=true) in the same turn.

5. Commit your fix with a `[Fix]` message describing what broke, then push to the PR branch:

   git add -A && git commit -m "[Fix] <description>"
   git push

   Pushing re-triggers CI; the coordinator will watch the new run.

## When to report stuck instead of guessing

Stop and return STATUS: stuck if the failure is infrastructure or flake you can't fix in scope, the failure is not reproducible and not diagnosable after honest investigation, or fixing it would require decisions the issue doesn't support.

## Return format

STATUS: fixed | stuck

SUMMARY:
<what was failing and what you changed>

CHECKS:
- <each validation command>: pass | fail (details)

BLOCKER (only if STATUS is stuck):
<what's failing, what you tried, what input is needed>
```

## Step 5: Final report

Tell the user:
- Which issue was implemented
- The PR URL
- How the PR merged: auto squash merge after green CI, direct merge after green CI, administrative squash merge after a verified billing failure and fresh local validation, or why it isn't merged
- If the billing fallback ran, the explicit GitHub billing error, the exact local validation commands that passed, and confirmation that the merged SHA matched the locally validated PR head
- If the watch-and-merge loop ran, how many CI-fix rounds it took and what was fixed each round
- The consolidated review summary from the ship-it subagent (Standards/Spec preflight, iterative rounds, findings, what was fixed, what was dismissed with rationale)

The user comes back to a merged (or about-to-merge) PR and a closed issue, and a main-session transcript that's still readable rather than a wall of test output and refactor diffs.
