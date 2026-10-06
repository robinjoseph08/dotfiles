---
name: batch-issues
description: Take a batch of ready GitHub issues to merged pull requests in parallel, one worktree and agent pipeline per issue, with independent QA before each ship.
disable-model-invocation: true
---

# Batch Issues

Run several small, independent GitHub issues through the same pipeline at once: implement, QA, ship. You are the coordinator. You never edit code yourself; you dispatch agents, judge their reports, and keep the batch moving. One issue's trouble must never stall the others.

Arguments: issue numbers, optionally a model for the agents (default `opus`). Everything repo-specific (setup command, check command, worktree layout, labels, PR title format, issue body conventions) comes from the repo's `CLAUDE.md`, `AGENTS.md`, and `docs/agents/`; read them before step 1 and pass the relevant pointers into every prompt.

The prompt templates for the three agent roles live in [`PROMPTS.md`](PROMPTS.md). Read it when you reach step 2.

## 1. Read the issues and set up worktrees

Read every issue with its comments. Note the acceptance criteria, any triage brief, and any decision the issue leaves open; those decisions are yours to make unless they materially change scope, in which case surface them to the user without blocking the batch.

Then read each issue's existing dependencies from the tracker (on GitHub, `gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by`). An issue whose blocker is still open does not start in this batch, even when the blocker is in the same batch: drop it from this run, or hold it until the blocker's PR has merged and then create its worktree off the new default branch. Tell the user which issues you held and why. A recorded block is the owner's decision; do not overrule it because the overlap looks small or the edits fall in different hunks, and do not swap it for "ship them one after the other".

Before creating worktrees, map each issue to the files and symbols it will touch (the issue's file references plus a quick grep) and look for overlap between issues. Two issues that edit the same handler, the same test helper, the same route table, the same generated-type consumer, or the same `AGENTS.md` section must not run in the same batch: sequence them, and record the order with the tracker's native blocked-by relationship so the second one cannot start until the first has merged. The repo's branch protection is deliberately not strict (no "up to date before merge"), so two green PRs that both touch one file can land in an order their CI never tested; a semantic clash (a renamed field one side, a new consumer of the old name on the other) then breaks the default branch and needs a hotfix. Keeping overlapping work in separate, blocked tickets is cheaper than that hotfix. Do not propose making protection strict; the owner has chosen speed here.

Create one worktree per issue off the current remote default branch, named `<issue>-<slug>` with branch `wktr/<issue>-<slug>` (or the repo's convention), and run the repo's setup command in each, in parallel. Plain `git worktree add` is enough; skip multiplexer tooling.

Completion criterion: every issue is understood, every existing blocked-by relationship has been checked and any issue with an open blocker is held, overlapping issues are sequenced with native blocks, and every worktree exists, is set up, and sits on the same remote default commit.

## 2. Dispatch one implementation agent per issue

Launch all implementation agents in a single message so they run concurrently. Name them `impl-<issue>`. Use the implementation template in `PROMPTS.md`, filling in the worktree path, branch, base commit, a two-paragraph summary of the issue, and the repo pointers.

The template asks each agent for a final report capped at 5000 characters that ends in a QA checklist with commands and at least one revert check per fix. The cap matters: longer reports are truncated in transit and you lose the checklist.

While they run, expect noise. Each implementer's code-review step spawns reviewers whose reports are also delivered to you; read them for anything Important, then let the implementer handle them. Two stall patterns recur and both need a nudge:

- **Waiting on reviews that already landed.** An implementer says it is waiting for reviewer reports you have already seen. Send it the consolidated findings with your decision on each (fix, skip with reason, note in report) and tell it to proceed without waiting further.
- **Editing after reporting.** An implementer sends its final report, then keeps applying review items in the worktree. Before QA, tell it to finish, amend into its commit, and reply with only the new SHA. Once QA starts, **freeze** the branch: no amends, no rebases, until you say otherwise.

If a report arrives truncated, ask for the checklist alone, capped at 4500 characters.

Completion criterion: every issue has a committed, unpushed branch, a passing full check, a completed code review, and a QA checklist in hand.

## 3. Dispatch one QA agent per finished issue

As each implementation report arrives, launch a fresh agent named `qa-<issue>` with the QA template. Do not wait for the whole batch. Give it the commit SHA, the implementer's report verbatim as claims to verify, the checklist, and your own additions: anything a reviewer flagged that you want independently confirmed, any claim that sounds too convenient, and a scope check against the merge base.

QA never modifies tracked files. Mutation checks go through `go test -overlay` or edit-and-restore. Manual verification runs a freshly built binary on a free port with an isolated data directory in a per-agent scratchpad subdirectory (`scratchpad/qa-<issue>/`), never the main checkout's data and never a directory another agent created; the scratchpad is shared across every agent in the session, and a generic `manual/` directory has been overwritten by a second QA agent before. The full check is rerun only when the machine's one-minute load is low; concurrent full checks from several worktrees cause spurious docs-server timeouts and unit-test timeouts, so the implementer's passing run plus targeted reruns is acceptable evidence when load is high.

If the branch changes under QA (a late amend, a squash), tell QA the new SHA and whether the tree is identical (`git diff <old> <new>` empty) so it can keep its results. If the tree differs, QA re-checks the delta only.

Completion criterion: every issue has a verdict of MERGEABLE, MERGEABLE WITH NITS, or NEEDS FIXES with evidence per item.

## 4. Judge the verdict

- **MERGEABLE**: ship.
- **MERGEABLE WITH NITS**: ship as-is when the nits are cosmetic or are follow-ups. When a nit is a one-line fix (a doc sentence, a test comment, a missing assertion), send it to the implementer to amend and report the SHA, then ship. Never let a nit round-trip more than once.
- **NEEDS FIXES**: send the findings to the implementer, then QA the amended commit. Two failed rounds means stop and surface it.

Decisions that change user-visible behavior beyond the issue, or trade one risk for another (a longer timeout, a permission loosened), get surfaced to the user in your status updates with your recommendation. Keep shipping the other issues meanwhile.

Completion criterion: every issue is either cleared to ship or explicitly parked with a reason the user has seen.

## 5. Dispatch one ship agent per cleared issue

Launch `ship-<issue>` with the ship template. It invokes the `ship-it` skill and owns rebase, PR, CI, and squash merge. Tell it that review and QA already happened so it skips re-review unless a conflict resolution changes behavior, and give it the PR body content: what changed, why any judgment call went the way it did, test evidence, follow-ups found, and `Closes #<issue>`.

Warn it about siblings. Branches in the same batch often touch the same route table, the same `CLAUDE.md`, or refactor the same test helper; the second to merge rebases over the first. Name the likely conflicts and how to resolve them (keep both changes, renumber lists, keep one helper set and make every test compile against it). Check for migration timestamp clashes when two branches add migrations.

Ship agents sometimes describe a check as passed or a PR as merged before any tool output said so. The template tells them to report only what tool output showed; verify the merge yourself in step 6 regardless.

Completion criterion: every cleared issue has a PR with auto-merge armed or merged.

## 6. Verify and clean up

Fetch the remote default branch and confirm each merge commit is on it and each issue is closed. Then remove every worktree whose tree is clean and delete its local branch; remote branches are deleted by the merge. Leave any worktree that is dirty and say so.

Completion criterion: `git worktree list` shows none of the batch's worktrees, and every issue is closed by a merged PR.

## 7. Report and triage follow-ups

Report to the user: a table of issue, PR, and what shipped; the judgment calls made on their behalf; and the follow-ups that reviewers and QA surfaced. File nothing until asked.

Triage the follow-ups before presenting them. Three reviewers plus a QA agent per PR will always produce a list, and each round of fixes produces a list of about the same size, so the list is not a queue. Split it in two:

- **Worth filing**: security issues, data loss or corruption, and behavior a user would actually see (a wrong status a client acts on, a device that fails a sync, a broken flow). Say why each one qualifies in a sentence.
- **Noted and dropped**: everything else. Cosmetic inconsistencies, hardening of paths no user reaches, edge cases of edge cases, duplicated code, doc wording, test selectors. List them in one compact paragraph so the user knows they were seen, and do not attach a recommendation to file. They already live in the PR bodies.

Default to the second bucket. When nothing qualifies for the first, say so plainly rather than promoting a cosmetic item to fill it. Only run class-level sweeps for a "worth filing" item when the batch itself showed the class is large (several instances across packages); a sweep that turns up two more harmless cases is a sign to stop, not to file.

When asked to file, write each ticket in the repo's issue conventions with the exact files and line numbers from the review reports, a proposed fix, notes for the implementer, and the triage label the repo uses for agent-ready work. One ticket may bundle several items from the same code area when one implementer with that context fixes them cheaply together.

Completion criterion: the user has the table, the decisions, and the two-bucket follow-up list, and any requested tickets exist.
