---
name: ship-it
description: Ship current work through resumable preparation, review, validation, push, and PR stages. Use when the user says /ship-it, "ship it", "send it", "open a PR", or wants to push current work for review.
user-invocable: true
---

# Ship It

Ship reviewed work without making one agent carry the entire workflow.

## Coordinator model

The agent invoking this skill is the coordinator. It performs cheap discovery, maintains a durable checkpoint, launches independent reviewers directly, and delegates one bounded mutation or publication stage at a time. Agents that can change the working tree run serially.

The coordinator must not hand the full workflow to one subagent. It also must not depend on resuming an ephemeral agent ID. If a delegated stage stops, launch a fresh agent from Git, GitHub, and the checkpoint. Review agents never need to spawn child agents.

Stages:

1. Prepare the branch
2. Run Standards and Spec preflight review
3. Adjudicate and fix preflight findings in bounded batches
4. Run one normal review round
5. Adjudicate and fix that round in bounded batches
6. Verify a patch-equivalent base refresh when needed
7. Repair a failed final gate when needed
8. Run the final gate and push
9. Create or update the PR

## Global invariants

- Do not push until review has converged and the final CI-equivalent gate has passed.
- Every review pass uses a newly spawned independent reviewer subagent. Never reuse an implementation, coordinator, stage, or fix agent as a reviewer.
- Reviewers never modify files, commit, push, create reviews, or post PR comments.
- The coordinator launches review agents synchronously and in parallel where appropriate. Delegated mutation and publication stages run in the foreground. Never end a turn waiting for background notifications.
- Iterative fixes use targeted checks followed by the repository's normal full check.
- The complete CI-equivalent suite runs only in the final publish stage. A failed final gate may be repeated only after diagnosis and stabilization.
- In initial mode, the first push occurs after review convergence. In repair mode, each CI repair cycle gets one post-convergence push. Never push intermediate review fixes.
- Git and GitHub are authoritative. Treat checkpoint summaries as navigation, then verify actual state.
- Retry exhaustion is not a blocker until the coordinator fetches the remote default branch and proves the pinned base is still current. A newer base may already resolve the finding or invalidate its evidence.
- A conflict-free rebase of a converged diff may preserve review evidence only when `git range-diff` proves the feature commits patch-equivalent. It still requires one fresh integration verification against the rebased complete diff and the new upstream range before validation or push.
- Do not store secrets, expanded environment values, auth data, or full command logs in the checkpoint.

## Step 1: Discover the invocation

Run cheap commands directly:

```bash
git status --short --branch
git branch --show-current
git log --oneline -5
git rev-parse --show-toplevel
git rev-parse --absolute-git-dir
```

Discover the remote default branch rather than assuming `master` or `main`. Identify three command-agnostic validation tiers from caller context, repository instructions, workflows, and task-runner configuration:

1. **Targeted checks** for changed files and behavior.
2. **Full check** for the normal local lint, unit-test, type-check, and build gate.
3. **CI-equivalent suite** for every required check, including slower integration, browser, race, packaging, or topology checks.

One command may serve both the full-check and CI-equivalent tiers. Follow the repository's interface rather than assuming a task runner.

Also determine:

- interactive or autonomous mode
- issue or spec source, if any
- summary and test evidence supplied by the caller
- required PR body prefix, such as `Closes #123`
- current branch, existing remote branch, and existing PR

## Step 2: Create or resume the checkpoint

Use this worktree-specific path outside tracked files:

```bash
git_dir="$(git rev-parse --absolute-git-dir)"
checkpoint="$git_dir/ship-it-checkpoint-v1.md"
lock="$git_dir/ship-it-checkpoint-v1.lock"
```

Acquire the lock with an atomic directory creation and record `PI_SESSION_ID` plus a timestamp inside it. The same parent session may resume its lock. If another session owns it, interactive mode asks before taking over and autonomous mode stops. Remove a stale lock only after explicitly reconciling the checkpoint and Git state.

A new checkpoint contains:

```markdown
# Ship-it checkpoint v1

Status: active
Stage: prepare
Mode: initial
Completed base-refresh rounds: 0
Pending base-refresh round: <none>
Completed CI repair cycles: 0
Pending CI repair cycle: <none>
Hosted stale-check key: <none>
Completed hosted rerun requests: 0
Pending hosted rerun request: <none>
Final report state: pending
Final report path: <none>
Final report digest: <none>
Coordinator session: <PI_SESSION_ID or harness identity>
Working directory: <absolute path>
Branch: <branch or pending>
Default branch: <remote/default>
Base SHA: <pending>
Review cycle: 1
Reviewed HEAD: <pending>
Final-gate HEAD: <none>
Final-gate result: <not run>
Pushed HEAD: <none>
Autonomous: true|false
PR URL: <none>
Outcome: <pending>
PR verification attempts: 0
Blocker kind: <none>
Blocker fingerprint: <none>

## Caller context
- Spec source: <issue, PRD, or none>
- Summary: <bounded summary>
- Test evidence: <bounded summary>
- PR body prefix: <optional exact closing directive>
- Issue identity: <owner/repo#number and URL, or none>

## Validation tiers
### Targeted
- <commands or selection guidance>
### Full check
- <commands>
### CI-equivalent
- <commands>

## Preflight ledger
### Standards
Pending.
### Spec
Pending or no spec available.

## Normal review ledger
No rounds yet.

## Pending work
None.

## Stage history
- Initialized at <HEAD and timestamp>.
```

Write checkpoint changes atomically through an adjacent temporary file and rename when practical. Keep reports bounded, but preserve every finding, disposition, severity change, validation result, review-cycle invalidation, and commit SHA needed for the final report. Rebases and repair cycles archive prior review sections as history; they never delete findings.

### Resume rules

If a matching active checkpoint exists, reconcile it before launching a stage:

- Verify working directory and branch. Do not apply another branch's checkpoint.
- Compare checkpoint SHAs with `HEAD`, the remote branch, and any PR head.
- If a review was interrupted before being saved, discard that unsaved result and use fresh reviewers.
- A fix stage records its in-flight finding IDs before its first mutation. If it stops with a dirty tree or an unrecorded commit, route those same IDs to a fresh fix stage in recovery mode. Preserve their pending dispositions until that stage reconciles the diff, checks, and commit.
- Preparation records `In-flight base refresh` before rebasing. On interruption, recover the same recorded old/new identities, expected remote SHA, and Git rebase state before another fetch or mutation.
- Final repair records `In-flight final repair` before its first edit. A dirty tree or unrecorded commit routes the same failure fingerprint and starting SHA to a fresh final-repair agent in recovery mode; do not allocate or count another repair.
- If an unexplained commit exists after the recorded SHA, inspect it, preserve existing findings, record it as unreviewed recovery work, and require a fresh normal review.
- If preparation recorded a patch-equivalent refresh from a converged reviewed diff, require `integration-review` for the exact refreshed HEAD. Do not treat old reviewed-HEAD or final-gate evidence as current.
- If final validation was interrupted, rerun the entire publish stage before pushing unless the checkpoint already records a passing final gate for the exact current SHA.
- If the push completed but its response was lost, compare the remote SHA with local `HEAD`; do not push the same SHA again.
- If PR creation was interrupted, inspect `PR verification attempts` first. Count 2 blocks without another lookup or increment; count 1 permits one fresh idempotent lookup/upsert; count above 2 is invalid. Then find the PR by head branch and upsert it when eligible.
- Preserve caller-managed CI repair accounting. If a pending repair cycle's stage history already proves repair commit, fresh review, passing final gate, exact push, and verified PR update, reconcile it as completed atomically without rerunning side effects. Incomplete pending cycles resume from their actual stage.

Archive a stale checkpoint only when it belongs to completed or abandoned work. Keep blocked checkpoints for recovery.

## Step 3: Route one bounded stage at a time

Read the checkpoint and execute the stage named by `Stage:`.

Review stages are coordinated directly because ordinary stage subagents may not have access to the harness's Agent tool:

- For `preflight-review`, `normal-review`, and `integration-review`, read `stages/review.md`, launch the required fresh reviewer agents yourself, then persist their reports and transition the checkpoint exactly as that file specifies.
- Never ask a reviewer agent to launch another reviewer.

All other stages use a fresh foreground `general-purpose` agent for each invocation:

| Checkpoint stage | Instruction file |
| --- | --- |
| `prepare` | `stages/prepare.md` |
| `preflight-fix` | `stages/fix.md` |
| `normal-fix` | `stages/fix.md` |
| `final-repair` | `stages/final-repair.md` |
| `publish` | `stages/publish.md` |
| `pr` | `stages/pr.md` |

`hosted-rerun` is a caller-coordinated stage used only after hosted CI repair proves a report stale on an unchanged SHA. Ship-it does not publish or push in that stage; an autonomous caller such as AFK requests and watches the bounded hosted rerun.

Every delegated stage prompt must include:

- absolute working directory
- absolute checkpoint path
- expected stage and current `HEAD`
- absolute instruction-file path
- autonomous or interactive mode
- a reminder to read repository instructions
- a requirement to update the checkpoint before returning
- a requirement to return the structured result defined by its stage file

For fix stages, also include the exact pending finding IDs, a one-sentence summary of each, and each finding's failed-attempt count for the current review cycle. State explicitly when the fresh agent is making the second attempt. Do not merely say "read the findings and fix them." For a final repair, include the bounded failure summary and failed command. This proves the coordinator reconciled the state before delegation.

After every coordinator-run review or delegated stage:

1. Check actual Git status, `HEAD`, remote state when relevant, and checkpoint contents.
2. Verify the stage performed only its assigned responsibility.
3. Confirm checkpoint transition matches actual state.
4. If it returned `needs-input`, interactive mode asks the user and records the answer before rerouting; autonomous mode records a blocker and stops.
5. If a fix or verification-review stage returned `retry-needed`, verify the worktree is clean and every affected finding remains below exhaustion; the checkpoint must retain each affected finding with exactly one failed attempt. For a fix stage, also verify that failed candidate changes were reverted and successful work was committed. For a review stage, verify that `HEAD` and the worktree remained unchanged. Fetch the remote default branch before spending the second attempt:
   - If the base advanced, atomically preserve the attempt evidence and successful commits, set `Status: active` and `Stage: prepare`, and route preparation. The prepare stage rebases, archives the invalidated review cycle, clears its active attempt state, and requires fresh review.
   - If the base is unchanged, launch a fresh fix-stage agent for the second attempt. Never let one stage agent make both attempts.
   - If base freshness cannot be established, atomically set `Status: blocked` and `Stage: blocked`, preserve the unresolved finding and successful commits, record the lookup failure, and stop rather than assuming the base is current.
6. If a fix or verification-review stage returned `retry-exhausted`, verify the same clean, durable state and every affected finding's count before deciding the outcome. Exhaustion takes precedence when any affected finding has two failed attempts. Fetch the remote default branch again and compare it with the pinned base:
   - If the base advanced, use the same prepare recovery above.
   - If the base is unchanged, atomically set `Status: blocked` and `Stage: blocked`, preserve the unresolved worthwhile finding and successful commits, record both failed attempts, and stop.
   - If base freshness cannot be established, use the same explicit blocked transition as above.
7. If it reported any other blocker, set `Status: blocked` and `Stage: blocked`, preserve details, and stop. Structured blockers also record a stable kind and deterministic fingerprint so unchanged recovery attempts do not repeat automatically.
8. If the PR stage returns `retry-needed` because a fresh postcondition lookup could not verify the PR, verify the worktree and all local/reviewed/validated/pushed SHAs still match. The PR stage owns the single durable attempt increment. Preserve Stage `pr` and launch one fresh PR-stage agent when the recorded count is 1; block when it reaches 2. Never increment again in the coordinator, and never accept command output or a printed URL as proof that the PR exists.
9. Otherwise route the next stage from the checkpoint.

Do not poll or resume a failed stage agent. Spawn a fresh stage from the durable state.

## Review policy

### Integration refresh

A reviewed diff rebased onto an advanced default branch may use the integration-refresh path only when preparation was conflict-free and `git range-diff` proves every feature commit patch-equivalent. Preserve the complete finding ledger, adjudications, verified fixes, and review history. Record old and new base/head SHAs plus bounded patch-equivalence evidence. Invalidate reviewed-HEAD and final-gate attestations tied to the old SHA, then run one fresh integration reviewer over both the complete rebased diff and the upstream old-base-to-new-base range.

A clean integration verification transfers convergence to the new HEAD and routes to publish. A semantic interaction becomes a new normal finding and routes through normal fix and verification without erasing prior history. Any conflict resolution, changed patch, ambiguous range-diff, or non-converged prior review uses full preparation invalidation and fresh preflight instead.

### Preflight

The preflight review keeps Standards and Spec separate. It follows the code-review skill with the remote default branch as the fixed point.

- Standards checks documented repository rules and baseline design smells.
- Spec checks caller-supplied issue or PRD behavior.
- In autonomous mode with no spec, record `no spec available` rather than blocking.
- In interactive mode with no discoverable spec, ask the user before beginning preflight.

Preflight findings use these outcomes:

- **Fixed**: valid and worth addressing.
- **Not fixed**: valid, but the proposed change would make the result worse or is only a low-value smell.
- **Invalid**: factually wrong or inapplicable.

### Normal review

Round 1 uses three fresh reviewers in parallel:

- **Robustness**: bad inputs, error paths, boundary conditions, and false success gates.
- **Test strength**: plausible regressions that existing assertions would miss.
- **Surface accuracy**: user-facing text, docs, help, errors, and comments.

Rounds 2 and later use one fresh verification reviewer. Give it the accumulated ledger and every item marked Fixed since the preceding review. It must explicitly verify those fixes. If a fix is absent or incomplete, it reports the problem under the existing finding key rather than creating a duplicate. It should not repeat resolved, invalid, or cosmetic items without new evidence. A zero-finding report is terminal only when all fixes since the previous round were explicitly verified.

Every round reviews the complete branch diff against the pinned base. A prose-only fix may receive a scoped prose verification round.

### Finding value bar

A valid finding is worth fixing when at least one is true:

1. It improves runtime behavior.
2. It adds or tightens a test against a plausible regression.
3. It corrects factually wrong user-facing text, documentation, or comments.

Pure cleanup and readability preferences are cosmetic. Record them but do not apply them. Valid critical and important findings pass the value bar by definition; reclassify them with a reason if that sizing was wrong.

Assign stable IDs by final severity: `C1`, `I1`, `M1`, and `N1`. Preserve round, original severity, final severity, outcome, and reason.

Fix stages process at most three pending findings per invocation. After a fix batch, run targeted checks plus the normal full check and commit locally. Never push. A later fresh review verifies the resulting complete diff.

A fix-stage agent may record at most one failed implementation attempt for a finding. Before counting an attempt as failed, it must diagnose every failing targeted assertion. When the finding intentionally corrects behavior that a test encodes, the old assertion may be stale; update it only after verifying the corrected contract, then add or tighten coverage for that contract. A red assertion for the intentionally replaced behavior does not by itself make the fix attempt fail.

Stop and report a blocker before normal round 7. After two failed attempts to resolve the same finding, use the coordinator's retry-exhaustion base-freshness check above. Only an unchanged base turns retry exhaustion into a blocker. Do not silently waive an unresolved worthwhile finding.

When a required deterministic proof cannot be observed because the configured harness lacks the necessary capability, and production changes, cache manipulation, timing changes, retries, or weaker assertions would not create valid evidence, classify `evidence-unavailable`. Record the exact evidence, bounded approaches ruled out, and a fingerprint derived from the gate, check, environment, and missing capability. This is not a failed implementation attempt or ordinary repair round. It blocks unchanged automatic reruns until the capability or valid evidence method changes.

## Final validation and publication

The publish stage may proceed only when:

- the worktree is clean
- the checkpoint has no unresolved worthwhile findings
- review converged at the current `HEAD`
- the pinned default-branch base has not advanced

If the default branch advanced, return to `prepare` without overwriting the pinned reviewed base/head. Preserve convergence and the ledger as candidate evidence and record the newly observed base separately. Preparation rebases and chooses patch-equivalent integration verification or full review invalidation. If final validation fails, record a bounded failure summary and route to `final-repair`. Any repair commit requires a fresh normal review before another publish attempt.

On the successful path, run the complete CI-equivalent suite once against the exact reviewed commit. Fetch and recheck the pinned default branch immediately after the suite, then push without intervening file changes only if the base is still current. A remote branch already at local `HEAD` may skip the push, but it may skip the final gate only when the checkpoint records that exact SHA as successfully validated.

A force-with-lease push is standing-authorized for any branch other than the remote default branch. This authorization applies in interactive and autonomous mode and does not require separate user confirmation. Before rewriting a published non-default branch, fetch it, record its exact old remote SHA in the checkpoint, and later use `--force-with-lease` against that exact SHA. Never force-push the remote default branch. In repair mode, preserve previous review and publication history, review the repair cycle, rerun the final gate, and make only the final repair push. In integration-refresh mode, preserve the completed PR identity and all prior evidence, then use preparation's patch-equivalence decision before rerunning the required review and final gate.

After the push, the PR stage creates or updates the PR idempotently. The title follows repository conventions. The body includes any required prefix, `## Summary`, and `## Test plan`. Never post review comments.

## Completion and report

Publication completion has two distinct terminal outcomes:

- `complete-with-pr`: requires a freshly verified PR whose head branch and head SHA match the expected pushed branch and SHA, with its URL recorded.
- `nothing-to-ship`: requires an empty diff and no PR publication claim.

No other outcome may set `Status: complete` or `Stage: complete`. Command success, a printed URL, or a remote branch alone is not a completion postcondition.

Build the final response from the checkpoint:

1. PR URL.
2. Separate Standards and Spec preflight results, including every outcome and reason.
3. Number of normal rounds and fixes per round.
4. Every normal finding grouped by final severity and labeled with round and stable ID.
5. Targeted, full-check, and final CI-equivalent validation outcomes.
6. Push and PR outcome.

Nothing is hidden, including invalid and cosmetic findings.

Set `Status: complete` before reporting. After the report is safely delivered, remove the checkpoint and its lock. If delivery is interrupted, the complete checkpoint lets the same coordinator session reproduce the report and then remove both. An autonomous caller such as AFK may retain the completed checkpoint and lock through its downstream CI and merge loop, then remove them after its own final report.

## Edge cases

- **Empty diff**: if no diff exists against the remote default branch, verify and report an existing PR if present; otherwise set the distinct `nothing-to-ship` outcome. Never represent it as `complete-with-pr`.
- **Detached HEAD**: stop before preparation.
- **Worktree**: the absolute Git directory keeps checkpoints isolated per worktree.
- **Existing remote branch**: a non-default branch may be rewritten with force-with-lease against its recorded exact old remote SHA. Never force-push the remote default branch.
- **Existing PR**: update it only after the final reviewed SHA is pushed.
- **External edits during a stage**: stop and reconcile before continuing.
- **Base advances after convergence**: preparation may preserve review evidence only through the patch-equivalent integration-refresh path; otherwise it requires fresh preflight and normal review.
- **Base advances during review fixes**: every failed attempt triggers a coordinator base-freshness check. A current base gets at most one fresh-agent retry; an advanced base routes to preparation before another attempt or blocker.
- **Concurrent invocation**: if another active coordinator appears to own the same checkpoint, stop rather than race it.
- **No Notion tasks**: never create one unless the user explicitly requests it.
