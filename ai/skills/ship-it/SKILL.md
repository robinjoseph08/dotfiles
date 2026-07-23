---
name: ship-it
description: Ship current work by committing and rebasing locally, completing a Standards/Spec preflight and iterative code review through independent reviewer subagents, then pushing once and creating or updating the PR. Use when the user says /ship-it, "ship it", "send it", "open a PR", or wants to push their current work up for review.
user-invocable: true
---

# Ship It

Get the current work committed, reviewed locally, pushed once, and PR'd in one shot.

## Overview

This skill handles the full "I'm done coding, get this up for review" workflow. It figures out what state the repo is in and does the right thing at each step rather than failing on edge cases.

## Step 1: Assess the situation

Run `git status`, `git branch --show-current`, and `git log --oneline -5` to understand:
- What branch are we on?
- Are there uncommitted changes (staged or unstaged)?
- Are there untracked files that should be included?

## Step 2: Ensure we're on a feature branch

If on `master`, create a new branch. Derive the name from the uncommitted changes or recent commits:
- Look at what files changed and the nature of the changes
- Generate a kebab-case branch name like `add-dark-mode-toggle` or `fix-cover-cache-busting`
- Keep it short but descriptive (3-5 words max)
- Create and switch to it: `git checkout -b <branch-name>`

If already on a non-master branch, stay on it.

## Step 3: Commit uncommitted changes

If there are uncommitted changes (staged, unstaged, or untracked files):

1. Stage the relevant files. Use `git add` with specific file paths rather than `git add -A` to avoid accidentally including sensitive files or build artifacts. Check `.gitignore` — don't add ignored files. For untracked files, use your best judgment based on context to decide whether they belong in the commit — if you have low confidence because the files seem unrelated to the work on the branch, ask the user before staging them.
2. Write a commit message following the project's `[Category] Description` format. Pick the category that best fits:
   - `[Frontend]`, `[Backend]`, `[Feature]`, `[Feat]` for features
   - `[Fix]` for bug fixes
   - `[Docs]` for documentation
   - `[Test]`, `[E2E]` for tests
   - `[CI]`, `[CD]` for CI/CD
3. The message should summarize the overall change, not list individual files. Focus on the "why" — what does this change accomplish?
4. Commit normally (do not skip hooks with `--no-verify`).

If there are no uncommitted changes, skip this step.

## Step 4: Rebase off master

Check if the branch is behind master:

```bash
git fetch origin master
git log HEAD..origin/master --oneline
```

If there are commits on master that aren't in this branch, rebase:

```bash
git rebase origin/master
```

If the rebase has conflicts, and you feel confident that you can merge them correctly, do so. If not, stop and tell the user.

## Step 5: Review preflight and iterative fix loop

Before pushing or creating the PR, run the code-review skill once as a Standards/Spec preflight against the local branch diff. Resolve its findings, then run the existing review → validate → fix → re-review loop until a full round produces nothing worth fixing. Track the preflight and normal-loop findings separately so you can present one consolidated report at the end without collapsing their different review models.

**Do not push during this step.** Keep the initial commits and every review-fix commit local until the entire review loop converges. This ensures CI only sees the final reviewed branch state.

### Independent-review invariant

Every review pass must run in a newly spawned reviewer subagent. This includes both Standards/Spec preflight axes, every normal-loop lens, and every later re-review or scoped verification. The shipping agent coordinates the process, validates findings against the code, applies fixes, and maintains the findings ledger, but it must never substitute its own review for a reviewer subagent.

Keep each reviewer independent of implementation work:

- Never use an implementation agent, the shipping agent, or an agent that applied fixes as a reviewer.
- Spawn a fresh reviewer subagent for each pass. If ship-it is itself running inside a subagent, it must spawn child reviewer subagents.
- Give reviewers the diff, relevant repository standards or spec, base/head SHAs, commit-derived change summary, and any ledger needed to avoid duplicates. Do not give them implementation transcripts, private implementation reasoning, anticipated findings, or the shipping agent's conclusions.
- Let the shipping agent validate and fix findings only after the independent reviewer returns. Any fixes must then be checked by another fresh reviewer subagent.

### Standards and Spec preflight

Read the code-review skill at `~/.agents/skills/code-review/SKILL.md` and follow its full two-axis workflow once, with these ship-it-specific inputs and overrides:

- Use `origin/master` as the fixed point; do not ask the user to choose one.
- Use issue or spec context supplied by the caller first. Otherwise follow the skill's discovery process using commit messages, the branch name, and repository files. No PR is expected yet, so do not depend on PR metadata.
- If no spec exists during an interactive ship-it run, ask the user as the code-review skill directs. If ship-it is running autonomously with no human available, skip the Spec sub-agent and record `no spec available` instead of blocking.
- Run the Standards and Spec sub-agents synchronously and in parallel. The no-background-work and no-PR-comments rules below apply to these reviewers too.
- Preserve the Standards and Spec reports as separate axes. Do not merge or rerank their findings.

Validate every preflight finding against the cited standard, spec, and current code. Record one outcome and a concrete reason for each finding:

- **Fixed** — valid and worth addressing before the normal review loop.
- **Not fixed** — valid, but the proposed change would be worse than the current code or is only a low-value smell judgment.
- **Invalid** — factually wrong or inapplicable.

Treat a valid documented-standard violation or spec mismatch as worth fixing. Treat the code-review skill's smell baseline as judgment calls: fix a smell when it yields a concrete design improvement, and otherwise record why it is not worth changing.

If the preflight produces fixes:

1. Apply all worthwhile fixes.
2. Run targeted validation and the project's full required validation suite.
3. Commit the fixes locally using the project's `[Category] Description` format. Do not push yet.

Run this preflight only once. Do not rerun code-review after its fixes; the normal ship-it loop reviews the updated full branch diff, including every preflight fix.

### The normal loop

Repeat the following until a full review round produces zero findings that are both valid and worth fixing (per the value bar in 5b). A round whose findings are all invalid or all cosmetic is a clean round; one clean round exits the loop.

**5a. Run a full review.**

**Round 1 is a three-lens panel.** Spawn three reviewer subagents in parallel, each reviewing the entire local branch diff through a different lens:

- **Robustness lens**: runtime behavior on bad inputs. Error paths, parsing and success gates, silent failure modes, edge values (null, empty, missing fields), boundary conditions. Instruct it: "for every place the code decides success vs failure, ask what inputs pass the gate that shouldn't."
- **Test-strength lens**: would a plausible regression pass the suite? Assertion tightness, untested error branches, plumbing no test observes. Instruct it: "for each behavior, name a realistic code change that breaks it but passes all existing tests."
- **Surface lens**: user-facing and doc accuracy. Help text, error message wording versus the code's actual check, README claims versus behavior, comments describing things that don't exist yet.

Dedupe the three result sets before validating; the same issue found by multiple lenses is one finding.

**Never end your turn to wait for background work.** This matters most when ship-it itself runs as a subagent (for example under the afk skill): a subagent that stops to "wait for completion notifications" kills its own background children, and the notifications never arrive, so the whole workflow stalls. Spawn reviewer subagents synchronously (`run_in_background: false`; multiple synchronous Agent calls in one message still run concurrently). Run long validation commands (builds, E2E suites) in the foreground with a generous timeout, or if one must be backgrounded, block on it with TaskOutput (block=true) in the same turn until it finishes. Only end your turn when the loop has fully exited and the final report is ready.

**Rounds 2 and later use a single fresh reviewer subagent.** Their job is verifying fixes and catching what the panel missed, not re-discovery from scratch. Never reuse a reviewer from an earlier round. Give this reviewer the accumulated findings ledger (every prior finding with its outcome and reason, including dismissals and cosmetic non-fixes), and instruct it explicitly:

- Do not re-report anything already on the ledger unless a later fix made it worse. If you think a ledger item was mis-sized, say so by ID instead of reporting it as new.
- Only report findings that would pass the value bar in 5b (better runtime behavior, a test that catches a plausible regression, or a factually wrong statement).
- A zero-findings report is the expected terminal state of a healthy loop, not a failure to do the job. Do not stretch for marginal findings to justify the round.

For each reviewer:

- Spawn a fresh reviewer subagent first; never perform the review in the shipping agent's context.
- **If the `requesting-code-review` skill is available** (check the available skills), instruct the reviewer subagent to use it. It's purpose-built for code review and knows how to check against project conventions.
- **If it's not available**, ask the reviewer subagent to review the local diff (`git diff origin/master...HEAD`) for correctness, style, and potential issues.

Give every reviewer:
- What was implemented (summarize from the commits)
- The base SHA (`origin/master`) and head SHA (`HEAD`)
- A brief description of the change
- Its lens (round 1 only)
- An explicit instruction to categorize each finding by severity (critical / important / minor / nit) and to return findings as structured text

**Every round reviews the entire local branch diff, not just the new changes.** Fixes can introduce new issues or affect other parts of the code, so re-review from scratch each round.

**5b. Validate each finding.** For every finding the reviewer returns, determine whether it's genuinely valid — read the relevant code, check the reviewer's claim, and decide. Record your validation decision and a brief reason for each finding. A finding can be:
- **Valid** — the reviewer is correct and the issue is worth addressing
- **Invalid** — either the reviewer is factually wrong (misread the code, concern doesn't apply, behavior is intentional), OR the finding is technically accurate but not worth doing (e.g., the "fix" would be worse than the status quo, purely stylistic in a way that doesn't match project conventions). Always record the concrete reason.

You may also **reclassify severity** during validation if the reviewer mis-sized the issue (e.g., a "critical" that's really a nit, or a "minor" that's actually important). Record the original severity, the new severity, and why you changed it. Treat the reclassified severity as authoritative for the rest of the loop.

Do not dismiss findings just because they feel minor or annoying. Dismiss only when you have a concrete reason.

**Then apply the value bar to each valid finding.** A valid finding is **worth fixing** if at least one of these holds:

- (a) fixing it changes runtime behavior for the better
- (b) it adds or tightens a test that would catch a plausible regression the existing suite would miss
- (c) it corrects a factually wrong statement in user-facing text, docs, or comments

Valid `critical` and `important` findings pass the bar by definition; if one seems not to, it is probably mis-sized, so reclassify it.

Findings that pass none of the three are **valid but cosmetic**: record them for the report, but do not fix them, and they do not count against loop exit. This explicitly includes changes that would arguably make the code cleaner or easier to read; judging that reliably is too error-prone, so cosmetic findings are never applied during the loop. They are surfaced in the final report so the user can cherry-pick any they want as follow-ups. When genuinely unsure whether a finding passes the bar, fix it.

**5c. Fix every finding that passed the value bar.** Severity does not gate this step; a nit that passes the bar gets fixed, and a minor that fails it does not.

  - A note about scope: In most cases, we want to leave code better than we found it. If we fixed something and find that we're doing it the old/wrong way somewhere else, it is in scope to fix all other locations so we don't have to make another PR to fix that later.
  - A note about size: Even if it's a small change, don't consider it "not worth the churn". Commits are cheap, and everything will be squashed anyway. If it passes the bar, do it.
  - A note about consistency: While generally, being consistent is good, if we never improve anything because it would make it "inconsistent compared to other callsites", then we'd never improve anything. If anything, it would make more sense to update other callsites to be consistent with the correct way to do things.
  - A note about conventions: if a fix introduces or amends a convention (a glossary entry, naming rule, or doc policy), apply it across the entire tree in the same commit and state the rule in one place only. Later rounds enforcing a convention an earlier fix round created is churn; finish the sweep when the convention lands.

Before committing, perform implementation sanity checks on the fix diff: exercise any error or cancel paths the fix adds, and sweep for collateral drift, meaning comments, docs, UI copy, and enumerations anywhere in the tree that the fix just invalidated. Update those in the same commit. This is part of applying the fix, not a substitute for the fresh reviewer subagent required after every fix round.

If anything was fixed in this step:
1. Commit the fixes locally (follow the project's `[Category] Description` format; a `[Fix]` prefix is usually appropriate).
2. Do not push yet.
3. Go back to step 5a and run another review round, scoped to what this round's fixes could have broken:
   - If any fix changed runtime behavior or tests, run a full review round as usual.
   - If the fixes only touched prose (docs, comments, UI copy), have the next reviewer verify just those fix commits and the files they touch. Prose cannot regress runtime behavior, so a clean scoped round exits the loop without another full branch pass.

If no fixes were applied in this step, exit the loop.

**Convergence guard.** If three consecutive rounds have each produced nothing above minor severity, the loop is in its tail: real defects are exhausted and full rounds are mostly rediscovering marginal issues. After fixing the current round's findings, run one scoped verification of those fixes instead of another full round, and exit if it comes back clean. Critical or important findings always reset this guard and force full rounds again.

**5d. Accumulate all findings.** Across all rounds, keep a running list of every finding — every severity, both valid and invalid. Dedupe them (the same issue may be reported in multiple rounds, especially before a fix lands). Assign each deduped finding a stable **ID** based on its final (post-reclassification) severity: `C1, C2, …` for critical, `I1, I2, …` for important, `M1, M2, …` for minor, `N1, N2, …` for nit. IDs persist across rounds so the user can reference them.

For each, record:
- The ID (e.g. C1, I1, I2, M1, N1, etc)
- Which round it was found in
- The finding text
- Final severity (and original severity if reclassified)
- Validation outcome (fixed / cosmetic / invalid) and reason

### Reviewer must not post to the PR

**IMPORTANT: Do NOT post review comments to the PR itself** at any point — no `gh pr comment`, no `gh pr review`, no GitHub review comments, in any round. All review feedback stays in the conversation. Tell the reviewer subagent this explicitly when you spawn it, so it doesn't post either.

## Step 6: Push the reviewed branch

Only after the preflight and iterative review loop have fully converged, push the final reviewed branch state:

```bash
git push -u origin <branch-name>
```

This should be the first push performed by this workflow. If the branch already exists remotely, this should be the only push performed during this run.

If the push is rejected because the remote branch has diverged (e.g., after a rebase), ask the user before force-pushing. Do not force-push without confirmation.

## Step 7: Create or update the PR

Check if a PR already exists for this branch:

```bash
gh pr view --json number,title,url 2>/dev/null
```

**If no PR exists**, create one:
- The PR **title** must follow the `[Category] Description` commit message format, because after squash-and-merge this title becomes the commit message on master and feeds into changelog generation. If there's a single commit on the branch and its message already follows the format, use it directly as the PR title. For multiple commits, summarize the overall final change across all commits, including review fixes.
- The PR **body** should include:
  - `## Summary` with 1-3 bullet points describing the final reviewed change
  - `## Test plan` with a bulleted list (not a checklist) of how to verify the change works
- Use a HEREDOC for the body to preserve formatting:

```bash
gh pr create --title "[Category] Description" --body "$(cat <<'EOF'
## Summary
- ...

## Test plan
- ...
EOF
)"
```

**If a PR already exists**, check whether its title and body still describe the final reviewed scope. Update either one as needed. The title must follow the `[Category] Description` format:

```bash
gh pr edit --title "[Category] Updated description"
```

### Final report to the user

Once the review loop has exited and the PR has been created or updated, present a single consolidated report with:

1. **Code-review preflight.** Present the Standards and Spec axes separately. Include every finding with its **Fixed**, **Not fixed**, or **Invalid** outcome and reason. If the Spec axis was skipped, say why.
2. **Rounds summary.** "Ran N rounds of iterative review." If fixes were applied, briefly list what was fixed in each round. Do not count the preflight as a normal review round.
3. **All normal-loop findings, grouped by severity** (critical → important → minor → nit), with every point **labeled by its round number and ID** (`R1-C1`, `R2-I1`, `R1-M1`, `R3-N1`, …) so the user can reference them in follow-up. Within each group, show every deduped finding — including ones marked invalid. For each finding, show:
   - The ID and the finding itself
   - Its validation outcome: **Fixed**, **Cosmetic** (valid but did not pass the value bar, deliberately not applied), or **Invalid**
   - If severity was reclassified, note the original severity (e.g., "reclassified from important")
4. **Nothing hidden.** Even preflight or normal-loop findings you deemed invalid must appear in the report — the user gets to judge your validation calls. Do not silently drop anything.

Example structure:

```
## Code-review preflight

### Standards
- [Fixed] New parser duplicated the repository's required validation boundary; consolidated it behind the existing module.

### Spec
- No findings.

Ran 2 rounds of review.

Round 1: fixed 2 critical, 1 important, 2 minor, 2 nit.
Round 2: clean, nothing passed the value bar.

## Critical
- **R1-C1** [Fixed] SQL injection in search handler — unsanitized user input in raw query
- **R1-C2** [Fixed] Missing auth check on /users/:id/reset-password

## Important
- **R1-I1** [Fixed] Missing index on job_logs.job_id causing slow deletes
- **R2-I2** [Invalid] "Race condition in worker pool" — reviewer missed the mutex at pkg/worker/pool.go:42

## Minor
- **R1-M1** [Fixed] Inconsistent error wrapping in new epub parser code
- **R1-M2** [Fixed] Similar pre-existing error wrapping inconsistency in pkg/cbz/
- **R2-M3** [Invalid] Suggestion to extract helper; would add indirection for a single call site
- **R2-M4** [Invalid] "Variable name shadowing"; name is intentional, shadows outer scope by design

## Nit
- **R1-N1** [Fixed] Comment on unrelated file line 87 is slightly out of date
- **R1-N2** [Fixed, reclassified from minor] Typo in new docstring added by this PR
- **R2-N3** [Cosmetic] Move test helper below the method block; readability preference only, not applied
```

## No Notion tasks

**Do not proactively create Notion tasks** for anything. If the user wants a Notion task, they'll ask.

## Edge cases

- **Empty diff**: If there is no diff between `origin/master` and `HEAD`, there is nothing to review or ship. If the branch is already pushed with a PR, report its current state. Otherwise report that the branch has no changes to ship.
- **Worktree**: This works from worktrees too. The branch is already non-master in a worktree, so step 2 is a no-op.
- **Multiple commits on the branch**: The PR title should summarize the overall change across all commits, not just the latest one. For a single commit, use its message directly if it already follows the format.
