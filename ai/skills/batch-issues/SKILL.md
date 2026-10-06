---
name: batch-issues
description: Take a batch of GitHub issues to merged pull requests in parallel, releasing held tickets as blockers merge and sharing research where useful, with one worktree and independent QA per issue.
disable-model-invocation: true
---

# Batch Issues

Run several small GitHub issues through the same pipeline: implement, QA, ship. Run independent issues concurrently and release dependent ones as their blockers merge. You are the coordinator. You never edit code yourself; you dispatch agents, judge their reports, and keep the batch moving. One issue's trouble must never stall unrelated issues.

Steps 2 through 6 run as a pipeline per issue, not as batch-wide barriers. Track each requested issue's blockers, stage, active agent IDs, worktree/base commit, current implementation SHA, research pointers, PR, and verified merge commit. Use stages `held`, `ready`, `implementing`, `qa`, `shipping`, `merged`, and `parked`; record a reason for anything held or parked. Never dispatch a second pipeline for an issue already active. Consume each agent report once and check its expected stage and active agent ID before advancing. For implementation results, verify the reported commit matches the assigned worktree's HEAD, then record that SHA. QA must cover that recorded SHA, or evidence explicitly reconciled under the delta-check rule in step 3. Ignore duplicate or superseded reports; verify ship results against hosted state in step 6.

Arguments: issue numbers, optionally a model for the agents (default `opus`). Everything repo-specific (setup command, check command, worktree layout, labels, PR title format, issue body conventions) comes from the repo's `CLAUDE.md`, `AGENTS.md`, and `docs/agents/`; read them before step 1 and pass the relevant pointers into every prompt.

The prompt templates for exploration, implementation, QA, and shipping live in [`PROMPTS.md`](PROMPTS.md). Read them before dispatching the corresponding role.

## 1. Read the issues and prepare the ready queue

Read every issue with its comments. Note the acceptance criteria, any triage brief, and any decision the issue leaves open; those decisions are yours to make unless they materially change scope, in which case surface them to the user without blocking the batch.

Read every page of each issue's existing dependencies from GitHub with `gh api --paginate repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by`. An issue with any open blocker enters `held`, even when the blocker is outside the requested batch. Tell the user which issues are held and why. Do not expand the batch to implement an external blocker without approval. A recorded block is the owner's decision; do not overrule it because the overlap looks small or the edits fall in different hunks, and do not swap it for "ship them one after the other".

Before creating worktrees, map each issue to the files and symbols it will touch using its references and a quick grep. Two issues that edit the same handler, test helper, route table, generated-type consumer, or `AGENTS.md` section must not run concurrently. They can stay in the same requested batch, but sequence them with GitHub's native blocked-by relationship and verify it with the corresponding GET endpoint. Respect existing dependency order when choosing which issue goes first; never add an edge that creates a cycle. Hold cyclic or otherwise unresolvable tickets and report the reason. The repo's branch protection is deliberately not strict (no "up to date before merge"), so two green PRs that both touch one file can land in an order their CI never tested; a semantic clash (a renamed field one side, a new consumer of the old name on the other) then breaks the default branch and needs a hotfix. Keeping overlapping work in separate, blocked tickets is cheaper than that hotfix. Do not propose making protection strict; the owner has chosen speed here.

Before releasing any issue, determine whether it needs the shared research described below. The **ready queue** contains requested, open issues whose native blockers are all closed, whose required shared research has returned with a verified notes path and no unresolved required facts, and whose work does not overlap an active issue. A ticket waiting for research stays `held` without a worktree; unrelated tickets can enter `ready` immediately. For a blocker implemented in this batch, also require the step 6 verification of its merged PR, closed issue, and merge commit on the fetched remote default branch. A passing implementation, QA verdict, armed auto-merge, or agent's completion notification alone does not release dependents.

Refresh this queue after each verified merge, required research result, or external blocker's state change. After the research gate passes and before each release, fetch the remote default branch, re-read every page of the candidate's native blockers, and update its touched-path mapping from research findings and issue changes. Create its worktree only when it is eligible, off that fetched default tip, named `<issue>-<slug>` with branch `wktr/<issue>-<slug>` or the repo's convention. Run setup, then recheck blockers immediately before dispatch. If a blocker reopened, hold the ticket and do not start implementation. On a later release, reuse an existing unstarted worktree only after verifying it is clean and updating it to the freshly fetched default tip; park it if that would discard local changes. Plain `git worktree add` is enough; skip multiplexer tooling. Worktrees in later releases have newer base commits than the first release.

### Shared research before implementation

When two or more issues need the same codebase exploration or external facts, dispatch a scoped exploration agent using `PROMPTS.md` rather than making each implementer repeat the reading. Skip this when the existing issue context is enough or the research is not reusable.

Give it the issue/spec pointers, precise research questions, relevant repo instructions, and source commit. Save its notes under a unique OS-temp directory such as `<tmpdir>/batch-issues-<unique-id>/research/`, outside the repo and all worktrees. The directory must be accessible to subsequent agents. Notes should include the source commit, relevant file paths, primary-source links, findings, and uncertainties. They are evidence, not decisions or a replacement for the issue's acceptance criteria.

Only tickets needing those findings wait for the exploration's actual result and a verified notes path. Dispatch unrelated ready tickets immediately. If research fails or required facts remain unresolved, hold the affected tickets with that reason and continue the others. Pass reusable findings as file pointers, not copied reports. For later releases, compare the note's source commit with the new worktree base for the referenced code paths. Have the implementer verify changed paths or request a scoped research update; unchanged code and external-source findings can still be reused. Retain the notes until every consumer has finished.

Completion criterion per issue: its preparation and blockers are recorded, any required overlap ordering is verified, and it is either held or parked with a reason, or released with verified research when needed and a worktree set up at its recorded base commit. Released issues may already be further along the pipeline; preparation is not a batch-wide barrier.

## 2. Dispatch one implementation agent per issue

For each release from the ready queue, launch its eligible implementation agents in a single message so they run concurrently. Name them `impl-<issue>` and move their stages to `implementing`. Use the implementation template in `PROMPTS.md`, filling in the worktree path, branch, base commit, a two-paragraph summary of the issue, repo pointers, and any shared-research paths with their source commits. Later releases use the same pipeline; do not wait for unrelated implementation, QA, or shipping agents.

The template asks each agent for a final report capped at 5000 characters that ends in a QA checklist with commands and at least one revert check per fix. The cap matters: longer reports are truncated in transit and you lose the checklist.

While they run, expect noise. Each implementer's code-review step spawns reviewers whose reports are also delivered to you; read them for anything Important, then let the implementer handle them. Two stall patterns recur and both need a nudge:

- **Waiting on reviews that already landed.** An implementer says it is waiting for reviewer reports you have already retrieved. Forward the actual results and consolidated findings with your decision on each, then let it proceed once every blocking reviewer is accounted for. A missing result is still a blocker, not a timeout to waive.
- **Editing after reporting.** An implementer sends its final report, then keeps applying review items in the worktree. Before QA, tell it to finish, amend into its commit, and reply with only the new SHA. Once QA starts, **freeze** the branch: no amends, no rebases, until you say otherwise.

If a report arrives truncated, ask for the checklist alone, capped at 4500 characters.

Completion criterion for each implemented issue: a committed, unpushed branch, a passing full check, a completed code review, and a QA checklist in hand.

## 3. Dispatch one QA agent per finished issue

When the current implementation agent's report is accepted and its SHA is verified against the worktree, move that issue from `implementing` to `qa` once and launch a fresh agent named `qa-<issue>` with the QA template. Do not wait for the whole batch. Give it the commit SHA, the implementer's report verbatim as claims to verify, the checklist, any relevant shared-research pointers, and your own additions: anything a reviewer flagged that you want independently confirmed, any claim that sounds too convenient, and a scope check against the merge base.

QA never modifies tracked files. Mutation checks go through `go test -overlay` or edit-and-restore. Manual verification runs a freshly built binary on a free port with an isolated data directory in a per-agent scratchpad subdirectory (`scratchpad/qa-<issue>/`), never the main checkout's data and never a directory another agent created; the scratchpad is shared across every agent in the session, and a generic `manual/` directory has been overwritten by a second QA agent before. The full check is rerun only when the machine's one-minute load is low; concurrent full checks from several worktrees cause spurious docs-server timeouts and unit-test timeouts, so the implementer's passing run plus targeted reruns is acceptable evidence when load is high.

If the branch changes under QA (a late amend, a squash), tell QA the new SHA and whether the tree is identical (`git diff <old> <new>` empty) so it can keep its results. If the tree differs, QA re-checks the delta only.

Completion criterion for each QA'd issue: a verdict of MERGEABLE, MERGEABLE WITH NITS, or NEEDS FIXES with evidence per item.

## 4. Judge the verdict

Accept a verdict only from the recorded QA agent while the issue is at `qa`, for the current implementation SHA or evidence explicitly reconciled under step 3. Record acceptance before dispatching fixes or shipping so duplicate reports cannot repeat those actions.

- **MERGEABLE**: ship.
- **MERGEABLE WITH NITS**: ship as-is when the nits are cosmetic or are follow-ups. When a nit is a one-line fix (a doc sentence, a test comment, a missing assertion), return the issue to `implementing`, send it to the implementer to amend and report the SHA, and reconcile QA evidence under step 3 before shipping. Never let a nit round-trip more than once.
- **NEEDS FIXES**: return the issue to `implementing`, send the findings to its implementer, then QA the amended commit through the same stage gates. Two failed rounds means park the issue and surface it.

Decisions that change user-visible behavior beyond the issue, or trade one risk for another (a longer timeout, a permission loosened), get surfaced to the user in your status updates with your recommendation. Keep shipping the other issues meanwhile.

Completion criterion for each reviewed verdict: the issue is cleared to ship, returned to `implementing` with findings assigned, or explicitly parked with a reason the user has seen. Parking a blocker does not release its dependents.

## 5. Dispatch one ship agent per cleared issue

For an issue with an accepted QA verdict, move it to `shipping` and launch `ship-<issue>` with the ship template exactly once. Record the ship agent's ID. It invokes the `ship-it` skill and owns rebase, PR, CI, and squash merge. Tell it that review and QA already happened so it skips re-review unless a conflict resolution changes behavior, and give it the PR body content: what changed, why any judgment call went the way it did, test evidence, follow-ups found, and `Closes #<issue>`.

Warn it about siblings. Branches in the same batch often touch the same route table, the same `CLAUDE.md`, or refactor the same test helper; the second to merge rebases over the first. Name the likely conflicts and how to resolve them (keep both changes, renumber lists, keep one helper set and make every test compile against it). Check for migration timestamp clashes when two branches add migrations.

Ship agents sometimes describe a check as passed or a PR as merged before any tool output said so. The template tells them to report only what tool output showed; verify each merge yourself in step 6 as it happens. An armed auto-merge remains `shipping`: keep observing hosted state until it merges or reaches a genuine blocker.

Completion criterion for each cleared issue: it enters `shipping` with a PR and remains there until its merge is verified or it is explicitly parked.

## 6. Verify each merge, release dependents, and clean up

As each PR merges, inspect hosted state to confirm it merged into the expected default branch, fetch that branch, verify its actual merge commit is on it, and confirm the issue is closed. Only then mark the issue `merged` and refresh the step 1 ready queue. Dispatch newly eligible tickets immediately; do not wait for other PRs or batch cleanup.

Remove only verified-merged worktrees whose trees are clean and delete their local branches. Leave dirty worktrees and any worktrees for held or parked issues intact, and report them.

If the ready queue is empty but other agents or PRs are active, keep advancing those pipelines. If only held or parked issues remain and no in-batch work can unblock them, report their blockers and stop this run without claiming completion. Do not spin indefinitely on external blockers. The final report must distinguish merged, held, and parked issues.

Completion criterion: every requested issue is either closed by a verified merged PR or explicitly held or parked with a reason. Clean worktrees for merged issues are removed, and any remaining worktrees are listed.

## 7. Report and triage follow-ups

Report to the user: a table of issue, PR, and what shipped; the judgment calls made on their behalf; and the follow-ups that reviewers and QA surfaced. File nothing until asked.

Triage the follow-ups before presenting them. Three reviewers plus a QA agent per PR will always produce a list, and each round of fixes produces a list of about the same size, so the list is not a queue. Split it in two:

- **Worth filing**: security issues, data loss or corruption, and behavior a user would actually see (a wrong status a client acts on, a device that fails a sync, a broken flow). Say why each one qualifies in a sentence.
- **Noted and dropped**: everything else. Cosmetic inconsistencies, hardening of paths no user reaches, edge cases of edge cases, duplicated code, doc wording, test selectors. List them in one compact paragraph so the user knows they were seen, and do not attach a recommendation to file. They already live in the PR bodies.

Default to the second bucket. When nothing qualifies for the first, say so plainly rather than promoting a cosmetic item to fill it. Only run class-level sweeps for a "worth filing" item when the batch itself showed the class is large (several instances across packages); a sweep that turns up two more harmless cases is a sign to stop, not to file.

When asked to file, write each ticket in the repo's issue conventions with the exact files and line numbers from the review reports, a proposed fix, notes for the implementer, and the triage label the repo uses for agent-ready work. One ticket may bundle several items from the same code area when one implementer with that context fixes them cheaply together.

Completion criterion: the user has the table, the decisions, and the two-bucket follow-up list, and any requested tickets exist.
