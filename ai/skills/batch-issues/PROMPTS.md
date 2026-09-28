# Batch Issues: agent prompt templates

Three roles, one template each. Fill every `<placeholder>`. Keep the repo pointers exact; agents have no other way to learn the conventions. Every template repeats three rules because each agent starts with an empty context: stay inside the worktree, never use bare `git stash`, no em-dashes anywhere.

## Implementation agent

```
You are implementing GitHub issue #<n> in the <owner/repo> repo. Work at a medium level of effort: be thorough on correctness, but don't gold-plate.

WORKTREE: <path> (branch <branch>, created off origin/<default> <base-sha>, setup already run). Do ALL work inside this directory. Never cd to the main checkout or other worktrees. Other agents are working in sibling worktrees concurrently; do not touch them. Never use bare `git stash`.

Check the project's root CLAUDE.md and any relevant subdirectory CLAUDE.md files (<list the ones that apply>) for rules that apply to your work. These contain critical project conventions, gotchas, and requirements. Violations of these rules are review failures. Also read <AGENTS.md / ADRs / a precedent commit to study, if any>.

THE ISSUE: run `gh issue view <n> --comments` to read it in full. Summary: <two paragraphs: the defect or change, the decision if the issue left one open, the acceptance criteria, what is out of scope, which docs must change>.

PROCESS (this is the /implement workflow):
1. Follow Red-Green-Refactor strictly: write the failing test first, run it and confirm it fails, then implement, then confirm it passes. <Name the Red test the issue implies.>
2. Run targeted checks regularly: <repo's lint and test commands for this stack>.
3. When done, run the full <repo's full check command> once. It may wait behind another worktree's run; that's expected. It must pass. If it fails only on <known load-sensitive parts, e.g. docs e2e server timeouts or 15s unit-test timeouts> while `uptime` shows heavy load, rerun the failed part alone, then rerun the full check when the load is under about 20; report each attempt.
4. Then invoke the `code-review` skill (via the Skill tool) on your work and fix every valid finding. Your reviewers deliver reports to you by message; if a report hasn't arrived within a few minutes of that reviewer finishing, proceed with what you have rather than waiting.
5. Commit to the current branch with a message in the `<repo's [Category] format>` from CLAUDE.md. Do NOT push, do NOT open a PR. Do not use em-dashes anywhere in code, docs, or commit messages.

FINAL REPORT (keep it under 5000 characters so it isn't truncated; be concrete):
- What you changed (files, behavior), and any decision you made on your own that the user might want to know.
- Results of the full check (pass/fail, verbatim failing output if any) and of the code review (what you fixed, what you declined and why).
- A QA CHECKLIST: a numbered list of specific, independently verifiable items a second agent can check without your context, each with a command, including at least one revert or mutation check per fix ("remove X, test Y fails"). Mark items that require a running app or manual testing separately.
```

## QA agent

```
You are a QA agent double-checking an implementation of GitHub issue #<n> in the <owner/repo> repo. You did not write the code. Be skeptical and verify each item yourself, at a medium level of effort. Do not fix anything; report findings. Do not commit, push, or leave tracked files modified (for revert checks prefer `go test -overlay` or the stack's equivalent; if you must edit a tracked file, restore it with `git checkout -- <file>` afterwards; never use bare `git stash`). Throwaway scripts belong in your scratchpad.

WORKTREE: <path> (branch <branch>, commit <sha>; confirm `git status --porcelain` is empty). Do all work inside this directory. Other agents are working in sibling worktrees; do not touch them.

Check the project's root CLAUDE.md and <relevant subdirectory CLAUDE.md files> for rules. Violations are review failures, so check the change against them (<name the rules most likely to bite: test parallelism, migration rules, docs rules, naming>).

THE ISSUE: run `gh issue view <n> --comments`. Check every acceptance criterion.

THE IMPLEMENTER'S REPORT (verify, don't trust):
---
<paste the implementer's report verbatim>
---

QA CHECKLIST (run from the worktree):
<paste the implementer's checklist, then add:>
- Scope: `git diff <base-sha> --stat` lists only in-scope files; flag anything else.
- <Any reviewer finding or convenient-sounding claim you want independently confirmed.>
- <Conventions: em-dash count 0 in the diff; new tests follow the repo's parallelism rule; docs accurate against code; versioned docs untouched.>
- Full check: check `uptime`. If the one-minute load is under about 20, run <full check command> and report the result verbatim on failure; otherwise run <targeted commands> and state that the full check was NOT rerun by you.

MANUAL (attempt if feasible within about 15 minutes, else mark NOT VERIFIED with the reason): build the binary from this worktree, run it on a free port with an isolated data directory in your scratchpad (never the main checkout's data), and exercise <the user-facing paths the issue names>. Stop the server afterwards.

FINAL REPORT (under 4500 characters): for each checklist item and acceptance criterion, PASS / FAIL / NOT VERIFIED with one line of evidence. Bugs, convention violations, or concerns ranked by severity with file:line. Your judgment on <any decision the implementer made>. End with a one-line verdict: MERGEABLE, MERGEABLE WITH NITS (list them), or NEEDS FIXES (list them).
```

## Ship agent

```
Ship the work for GitHub issue #<n> (<owner/repo>) as a pull request and see it through to a squash merge into <default>. Invoke the `ship-it` skill via the Skill tool FIRST and follow it exactly.

WORKTREE: <path>, branch <branch>, commit <sha>, clean, based on origin/<default> <base-sha>. Do all work inside this directory. Other agents are working in sibling worktrees; do not touch them. Never use bare `git stash`. Never push to <default> directly.

Context for the ship-it skill's "Prepare" step: the work has ALREADY been reviewed with the code-review skill by the implementing agent (<summary of review outcome>) and independently QA'd by a second agent (<summary of QA verdict and evidence>). Do NOT re-run code-review unless a rebase conflict resolution changes behavior. After any rebase run <targeted check commands>.

REBASE onto the latest origin/<default> first. <Name sibling PRs that may have merged, the files they touch, the expected conflicts, and how to resolve each: keep both changes, renumber lists, keep one test-helper set and make every test compile against it. If both branches add migrations, check for a timestamp clash and rename if needed.>

Check the project's root CLAUDE.md for rules (PR title format `<[Category] ...>`, no em-dashes anywhere in the PR title or body). Violations are review failures.

PR details:
- Title: the commit subject from `git log -1 --format=%s`.
- Body: <what changed; why any judgment call went the way it did; docs updated; test evidence including the QA run; follow-ups found by review or QA, marked out of scope>. Include "Closes #<n>". End the body with the attribution lines given in your system-reminder, if any are present.
- Base: <default>.

Follow the ship-it skill for merge: if the default branch requires status checks, enable squash auto-merge once checks are pending and verify the request is recorded; otherwise wait for every check to finish before merging. Watch CI with `gh run watch --exit-status` or a `bash <<'EOF'` polling loop (macOS has no `timeout`, and zsh does not word-split); if it fails, diagnose and fix (commit, push) and re-verify. Do not weaken tests. After merge, confirm the merge commit is on origin/<default>. Do NOT delete the worktree or local branch. Report only what tool output actually showed; never describe a check as passed or a PR as merged unless a command output showed it.

FINAL REPORT (under 2500 characters): PR URL, final merge status, checks and outcomes, merge commit SHA on origin/<default>, how any conflicts were resolved, and anything that went wrong or needed a fix.
```
