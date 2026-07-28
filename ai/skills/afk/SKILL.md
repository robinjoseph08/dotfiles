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
- Route bounded implementation attempts and recover from interrupted attempts
- Launch ship-it reviewers directly and coordinate bounded mutation and publication stages
- Enable auto-merge and write the final report

What the subagents do:
- **Implementation subagents**: each attempt follows the implement skill for the feature/fix, runs targeted checks and the repository's normal full check, then leaves the work uncommitted for ship-it. If an attempt reaches its turn limit, a fresh continuation agent finishes from the shared working tree.
- **Ship-it reviewer agents**: fresh read-only agents launched directly by the AFK coordinator for Standards, Spec, and normal review passes
- **Ship-it stage agents**: each performs one bounded preparation, fix, final repair, validation and push, or PR stage using ship-it's worktree-specific durable checkpoint

Subagents share the main working tree. Implementation runs first, then read-only review passes and mutating ship-it stages run serially, so there are no concurrent mutations. Each mutating stage returns a tight structured summary and persists durable state outside tracked files. If a stage stops, the AFK coordinator launches a fresh stage from Git, GitHub, and the checkpoint instead of resuming an ephemeral agent ID.

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

Record the selected issue's canonical `owner/repo#number` identity and URL, not only its number. Compare its repository with the implementation repository. The later PR body uses exact `Closes #<N>` only for the same repository and exact `Closes owner/repo#<N>` for a cross-repository issue.

Then claim it:

```bash
gh issue edit <canonical-issue-url> --remove-label "ready-for-agent" --add-label "in-progress"
# Or: gh issue edit <number> --repo <canonical-owner/repo> ...
```

Note: if the `in-progress` label doesn't exist, create it.

## Step 2: Delegate implementation through recoverable attempts

Spawn one implementation attempt at a time. Each attempt does its code reading, test writing, and iteration in its own context. Limit every attempt to 100 turns so a runaway attempt eventually returns control to the coordinator. Use the harness-specific invocation below:

- **Pi**: use `subagent_type: "general-purpose"` with `max_turns: 100` on the Agent call.
- **Claude Code**: use the custom `afk-implementation` subagent from `~/.claude/agents/afk-implementation.md`. Its frontmatter sets `maxTurns: 100`. Invoke it in the foreground through Claude Code's Agent tool and do not pass Pi's unsupported `max_turns` call argument.

The working tree is the durable implementation state, so a fresh agent can continue if an attempt reaches the limit. Allow at most three implementation attempts total. A turn-limit interruption starts a fresh continuation attempt and does not by itself make the issue blocked. If the third attempt reaches its turn limit, report a blocker with the current implementation and validation state rather than starting another agent.

Before writing the brief, identify three command-agnostic validation tiers so the subagent does not guess. Check, in order: CI workflows (`.github/workflows/`), the project's CLAUDE.md and README, and the task runner config (Makefile, mise.toml, justfile, package.json scripts).

1. **Targeted checks** for the files and behavior being changed.
2. **Full check** for the repository's normal local gate, such as its standard lint, unit-test, type-check, and build command.
3. **CI-equivalent suite** for every check required before pushing, including slower integration, browser, race, packaging, or topology checks.

A repository may use one command for both the full check and CI-equivalent tiers. Put the discovered commands in both subagent briefs, including any quirks needed to match CI. Do not prescribe a task-runner-specific command when the repository defines another interface.

### Initial implementation prompt template

Give the first attempt everything it needs to work without coming back to you. Use the Pi or Claude Code subagent configuration above and a prompt along these lines (fill in the angle-bracketed parts):

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
   - Do not invoke code-review; the staged ship-it coordinator owns the Standards/Spec preflight and iterative review and fix loop in step 3.
   - Do not commit; leave the completed changes uncommitted for ship-it's prepare stage.
   - Use the repository-specific targeted checks and full-check command below.

3. After implementation, run the targeted checks for what you touched, then the repository's normal full check:

Targeted checks:
<targeted check commands for this repo, per area touched>

Full check:
<normal local validation command for this repo>

   Do not run the slower CI-equivalent suite here. Ship-it owns the single final CI-equivalent validation phase immediately before pushing. If a targeted check or the full check fails, fix it and rerun the affected checks until they pass.

   You are a subagent: never end your turn to wait for a background task, because ending your turn kills the task and its completion notification never arrives. Run long commands in the foreground with a generous timeout. If background work is unavoidable, use the harness's blocking result mechanism, such as Pi's `get_subagent_result` with `wait: true` or Claude Code's `TaskOutput` with `block=true`, in the same turn.

4. Before returning, run this self-review pass over your own work:
   - **Error branches**: every error return and failure path you added has a test, or you can state why not.
   - **Stale text sweep**: search help text, error messages, README, and comments for claims your change invalidated (old tool names, old preconditions). Check that every message describing a condition matches the code's actual check (for example "X is not set" versus a check for non-empty).
   - **Sibling symmetry**: where two code paths share a contract (such as create and resume), every plumbing or regression test on one has a mirror on the other, or a stated reason it doesn't apply.
   - **Doc honesty**: comments and interface docs describe what the code does now, not the planned end state.

5. Do not commit, push, or create a PR. The coordinator handles git operations. Leave changes uncommitted in the working tree.

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

### Implementation attempt recovery

When an implementation attempt returns, inspect both its structured result and the harness's subagent result metadata. Any result that says the attempt reached, exceeded, or wrapped up at its turn limit is an interruption, even if the agent labeled its own result `STATUS: success` or `STATUS: blocked`.

After an interrupted attempt:

1. Inspect the shared working tree with `git status --short`, `git diff --stat`, and any other cheap state needed to understand what remains. Do not reset or discard the interrupted attempt's changes.
2. Start a fresh attempt using the same harness-specific configuration: Pi's `general-purpose` agent with `max_turns: 100`, or Claude Code's `afk-implementation` agent with `maxTurns: 100` supplied by its definition. Do not resume or depend on the interrupted agent ID.
3. Give the continuation agent the complete original issue and validation tiers, plus:
   - The interrupted attempt's full returned summary, if any
   - The current `git status --short` and `git diff --stat`
   - Which checks passed, failed, or still need to run
   - The instruction below

```text
This is implementation continuation attempt <N> of 3. A previous attempt reached its turn limit, and its uncommitted changes remain in the shared working tree. Treat the working tree, not the previous summary, as the source of truth. Inspect the existing diff and relevant code before editing. Preserve correct completed work, finish or repair anything incomplete, and rerun the targeted checks and full check after the final edit. Return the same structured implementation result. Do not commit, push, create a PR, or invoke code review.
```

A continuation agent follows the same implementation prompt and return format as the initial attempt. It must not assume that checks reported by an earlier attempt still cover the current tree. Only checks run after the latest edit count as final validation.

After each attempt:
- If the subagent result reports a turn-limit interruption and fewer than three attempts have run, launch the continuation attempt above.
- If the subagent result reports a turn-limit interruption on attempt three, report the blocker to the user, leave the issue in `in-progress`, and stop.
- If the attempt returns `STATUS: blocked` without a turn-limit interruption, report the genuine blocker to the user, leave the issue in `in-progress` (or restore `ready-for-agent` if that is more appropriate), and stop.
- If the attempt returns `STATUS: success` without a turn-limit interruption, continue to step 3 using that attempt's summary.

## Step 3: Ship and review through bounded stages

The AFK main session now acts as the ship-it coordinator. Do not spawn one end-to-end ship-it subagent.

1. Read `~/.agents/skills/ship-it/SKILL.md` completely and follow its coordinator protocol.
2. Initialize or resume ship-it's worktree-specific checkpoint with these AFK inputs:
   - `Autonomous: true`
   - issue body and comments as the Spec source
   - the exact closing directive as the PR body prefix: `Closes #<N>` for an issue in the implementation repository, otherwise `Closes owner/repo#<N>`
   - implementation SUMMARY, BEHAVIORS TESTED, and NOTES FOR PR BODY as caller context
   - the Targeted, Full check, and CI-equivalent validation tiers discovered in step 2
   - standing authorization to rewrite any non-default branch with force-with-lease against its recorded exact old remote SHA; never force-push the remote default branch
3. For `preflight-review` and `normal-review`, the AFK coordinator reads ship-it's review-stage instructions and launches the required fresh reviewer agents directly. Reviewers never launch child agents. For every other stage, route one bounded foreground stage agent using ship-it's stage files. Together these stages commit and rebase, adjudicate and fix findings in bounded batches, run the final gate, push, and upsert the PR.
4. After each stage, verify Git and checkpoint state before routing the next stage. If a stage stops or hits a turn limit, launch a fresh stage from the checkpoint. Never resume or depend on its agent ID.
5. If ship-it records a blocker, surface it and stop. Otherwise retain the completed checkpoint through the merge loop so its PR URL and review ledger remain available for the final AFK report.

All AFK review and fix stages are autonomous. They must not ask the absent user for decisions. When ship-it says interactive mode would ask, autonomous mode must use the skill's safe default or record a blocker.

## Step 4: Merge the PR

Before every merge or auto-merge command, read the canonical PR URL from the retained checkpoint and freshly verify that exact PR's state, `headRefOid`, body closing directive, and URL. Require `headRefOid` to equal the locally validated and pushed SHA and the worktree to be clean. If it is already merged, route to post-merge reconciliation. Any drift blocks before mutation.

Then try to enable auto squash merge for that exact verified PR:

```bash
gh pr merge <canonical-pr-url> --squash --auto
```

**If auto-merge is enabled**, do not consider the run finished yet. Watch the checks below until the PR merges or a failure needs attention. This is necessary because an Actions billing failure leaves auto-merge enabled forever even though no job can run.

**If auto-merge can't be enabled**, look at why:

- **The repository doesn't allow auto-merge** (the error mentions auto-merge is not allowed or not enabled for the repository, e.g. `enablePullRequestAutoMerge`). This is common and expected. Fall through to the watch-and-merge loop below rather than reporting a failure.
- **Any other reason** (required human approvals you can't satisfy, other branch protection you can't clear). Report it to the user and stop. Do not force-merge.

### Watch-and-merge loop

Babysit CI whether auto-merge was enabled or unavailable. Merge the moment it is safe. Cap ordinary CI failures at **3 fix rounds** and default-base integration refreshes at **3 refresh rounds**, counted separately. If either budget is exhausted, stop with the retained checkpoint and exact current state.

On every entry or resume, reconcile pending accounting before watching checks:

- For `Pending CI repair cycle`, when durable stage history proves repair commit, fresh review, passing final gate, exact push, and verified PR update, atomically advance `Completed CI repair cycles` and clear pending without rerunning side effects. Otherwise resume from the recorded stage without counting it.
- For `Pending base-refresh round`, when durable history proves preparation, required review, passing final gate, and verified PR update, atomically advance `Completed base-refresh rounds` and clear pending. Push proof may be either the recorded exact force-with-lease result or the crash-recovery postcondition that the freshly fetched remote and PR heads equal the exact validated refreshed head while the checkpoint retains the expected old remote SHA. Otherwise resume from the recorded stage without allocating another round.
- For `Pending hosted rerun request`, first reconcile hosted runs for the bound SHA and stale-check key. If the requested rerun exists, atomically advance `Completed hosted rerun requests`, clear pending, and watch it. If it does not appear after a bounded propagation check, block as `hosted-rerun-request-uncertain`; never reissue the uncertain request or allocate another merely because the coordinator restarted.

1. **Reconcile authoritative PR state, then watch checks.** At the start of every loop or resumed coordinator, fetch the expected PR state, `headRefOid`, and `mergeCommit.oid` before issuing any merge command. If it is already `MERGED` at the validated PR head, record the distinct merge identity and route directly to post-merge reconciliation; never invoke merge again. Otherwise watch the checks:

   ```bash
   gh pr checks --watch
   ```

   This blocks until every check on the latest commit completes, then exits 0 if all passed and non-zero if any failed. If it reports there are no checks at all, confirm the repository genuinely has no CI workflow for the PR before treating that as green; a newly pushed commit can have a short delay before its checks appear.

2. **If CI is green:**

   - If auto-merge is enabled, verify that GitHub completes the merge. If it remains open briefly after checks pass, inspect unmet requirements with `gh pr view` before deciding whether to wait or report a blocker.
   - If auto-merge is unavailable, merge directly:

     ```bash
     gh pr merge <canonical-pr-url> --squash
     ```

   If this merge is rejected because checks haven't finished yet (a race right after a push), go back to step 1 and watch again.

   If auto-merge remains open or direct merge is rejected only because the default branch advanced and branch protection requires an up-to-date PR head, do not report a terminal blocker and do not merge administratively:

   1. Verify the PR head, local HEAD, and checkpoint pushed/reviewed SHA still match exactly and the worktree is clean. External head drift blocks rather than being overwritten.
   2. Block when three completed base-refresh rounds are already recorded. Atomically set `Pending base-refresh round` to the next round together with `Status: active`, `Mode: integration-refresh`, `Stage: prepare`, the exact old PR head, and newly fetched default-base SHA. Do not advance `Completed base-refresh rounds` yet.
   3. Preserve all review, finding, validation, push, and PR history in that same transition.
   4. Follow ship-it's optimistic base-refresh path. A conflict-free patch-equivalent rebase gets one fresh integration verification; conflicts, changed patches, or ambiguous evidence require full review. Then rerun the CI-equivalent gate on the refreshed reviewed head, push only with exact force-with-lease against the recorded old PR head, and upsert the same PR.
   5. After exact push and verified PR update, or after crash reconciliation freshly proves both remote and PR heads equal the exact validated refreshed head under the checkpoint's recorded old-remote lease, atomically set `Completed base-refresh rounds` to the pending round and clear `Pending base-refresh round`. Return to step 1, watch checks for the refreshed SHA, and retry ordinary squash merge. Prefer the repository's merge queue when one is available; the local refresh path is for repositories without one.

3. **If CI is red**, list the failing checks (cheap, keep it in the main context):

   ```bash
   gh pr checks
   ```

   Inspect the failed run before delegating a code fix. Get the run URL from `gh pr checks --json name,state,link,bucket`, then use the bounded extractor first:

   ```bash
   ~/.agents/skills/afk/scripts/extract-ci-failures.sh --repo <owner/repo> <run-id-or-url>
   ```

   It reports failed jobs and capped failed-step logs without flooding the coordinator context. If its bounded output does not expose the cause, inspect only the relevant job or API object with `gh run view` or `gh api`; do not pull the entire workflow log by default. Classify it as an Actions billing failure only when GitHub explicitly says the job was not started because of a billing/payment problem or an Actions spending limit. Do not infer billing from a generic startup failure, missing logs, a cancelled/skipped job, a runner outage, or another infrastructure error.

   - **Verified Actions billing failure:** use the billing fallback below.
   - **Any ordinary CI failure:** reopen the retained ship-it checkpoint in repair mode instead of spawning a monolithic CI-fix-and-push agent:
     1. Verify the worktree and local branch match the PR's latest head SHA.
     2. Refuse to start when three completed ordinary repair cycles are already recorded. Atomically set `Status: active`, `Mode: repair`, `Stage: final-repair`, and `Pending CI repair cycle` to the next cycle number, but do not increment `Completed CI repair cycles`.
     3. Preserve every earlier review and publication ledger as history. Record the failing checks, failed command when known, and bounded extractor report under Pending work without storing full logs.
     4. Follow ship-it's staged coordinator protocol again. The final-repair stage first classifies the outcome. `evidence-unavailable`, external infrastructure, and stale reports block or return according to ship-it without consuming an ordinary CI-fix round. An actual repository repair proceeds through fresh review, final validation, push, and PR update.
     5. After an actual repository repair cycle completes its verified push and PR update, atomically set `Completed CI repair cycles` to the pending cycle number and clear `Pending CI repair cycle`. Preserve the commit, review, validation, push, and PR evidence. Then go back to step 1 and watch the new CI run. If any stage blocks, report it and stop.

   If hosted final-repair returns `stale` with `Stage: hosted-rerun`:

   1. Require an unchanged PR head, exact-SHA passing local final gate, and a stable stale-check key derived from SHA, workflow/check identity, failed command, and normalized failure signature. Exclude run and attempt IDs. Clear `Pending CI repair cycle` without incrementing the completed repair count. When the key or SHA changes, atomically reset completed and pending hosted-rerun accounting for the new incident.
   2. Reconcile whether a newer rerun of the same source workflow/check already exists for that SHA and key. Watch an existing rerun rather than duplicating it.
   3. If no rerun exists and fewer than two completed requests are recorded, atomically set `Pending hosted rerun request` to the next request number before requesting the rerun. After GitHub exposes that rerun, atomically advance `Completed hosted rerun requests`, clear pending, and watch it. On restart, reconcile a pending request before issuing anything again. If no corresponding rerun appears after the bounded propagation check, classify `hosted-rerun-request-uncertain`, retain pending state, and block rather than reissuing a request whose prior outcome is unknown. Do not route through publish, push the unchanged SHA, create a no-op commit, or consume a code repair cycle.
   4. If rerun is unavailable, or the same SHA and key still have the identical no-progress failure after two completed requests, set `Blocker kind: hosted-check-no-progress`, set `Status: blocked` and `Stage: blocked`, retain the checkpoint, and stop. Never use administrative merge for this condition.

   Only completed repository repair cycles count toward the three-round CI-fix cap.

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

## Step 5: Post-merge reconciliation and final report

Before reporting completion:

1. Freshly verify the expected PR's `headRefOid` equals the locally validated PR-head SHA and the PR is `MERGED`. Record the distinct resulting `mergeCommit.oid` as the merge identity in the retained checkpoint before cleanup; a squash merge commit is not expected to equal the PR head. Then check the issue. If it is still open, wait only for a bounded closure-propagation window, such as two minutes at the normal poll interval, and recheck without force-closing or otherwise mutating it. If it closes, continue. If it remains open, retain the completed checkpoint and lock, record a `post-merge-closure-pending` blocker with the verified merge identity, and stop for safe resume.
2. Remove only AFK-owned workflow labels from the closed issue, including stale `in-progress` and `ready-for-agent`. Preserve unrelated and human workflow labels. Freshly verify the owned labels are absent and every unrelated label observed before mutation remains.
3. Build the final report from the retained checkpoint. Atomically write it to `ship-it-final-report-v1.md` adjacent to the checkpoint, record its path and digest, and set `Final report state: ready`. This file is the durable delivery payload. Deliver that exact payload. When the harness permits post-delivery cleanup, set `Final report state: delivered` before removing the report file, completed checkpoint, and lock. If it does not, leave the ready report and checkpoint for Backlog or later reconciliation; `ready` means delivery may still be needed, while only `delivered` authorizes deletion.
4. Never remove the current worktree, local branch, Pi session, Backlog Lease, or historical logs from inside AFK. The verified merged outcome is Backlog's authority for idempotent Run finalization and worktree/branch cleanup.

Tell the user:
- Which issue was implemented
- The PR URL
- How the PR merged: auto squash merge after green CI, direct merge after green CI, administrative squash merge after a verified billing failure and fresh local validation, or why it isn't merged
- If the billing fallback ran, the explicit GitHub billing error, the exact local validation commands that passed, confirmation that the PR `headRefOid` matched the locally validated SHA, and the distinct resulting `mergeCommit.oid`
- If the watch-and-merge loop ran, how many CI-fix rounds and base-refresh rounds it took and what changed in each
- The consolidated review summary from ship-it's durable checkpoint (Standards/Spec preflight, iterative rounds, findings, what was fixed, what was dismissed with rationale)

After the final report is safely delivered, mark its durable state `delivered`, then remove the final-report file, completed ship-it checkpoint, and lock. If post-delivery cleanup is unavailable, leave the `ready` payload and checkpoint for Backlog or later reconciliation. Keep a blocked checkpoint and lock so the same AFK session can recover; a later session must explicitly take over the stale lock after reconciliation.

The user comes back to a merged (or about-to-merge) PR and a closed issue, and a main-session transcript that's still readable rather than a wall of test output and refactor diffs.
