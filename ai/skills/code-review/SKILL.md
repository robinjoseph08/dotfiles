---
name: code-review
description: Review code changes against project standards, intended behavior, and engineering risk. Use when the user asks to review a branch, PR, diff, or work in progress, and as a checkpoint after major work or before merging.
---

# Code Review

Review a clearly defined set of changes and return a concise, evidence-based report. Use judgment rather than trying to exhaust a generic checklist. Prefer a few meaningful findings over speculative or cosmetic feedback.

The review itself does not change code. Only make follow-up changes when the review is part of an active implementation request or the user asks for fixes.

## Establish the review scope

Determine the exact diff being reviewed, including whether uncommitted changes are in scope. Use the fixed point supplied by the user. If none was supplied, infer it from the development context when that is safe; otherwise ask.

Validate the revisions and make sure the diff is not empty. Gather enough surrounding code to understand the changes rather than reviewing isolated hunks.

Find the relevant sources of intent:

- Repository instructions and coding standards
- The issue, specification, plan, or user request that prompted the work
- Commit messages and other nearby context when useful

If there is no specification, say so. Do not invent one.

## Review independently along three axes

For a substantive review, run the applicable axes as independent, parallel subagents. Give each reviewer the review scope, relevant source material, and permission to inspect surrounding code and run focused checks. Treat these reviewers as blocking when their findings determine whether work can proceed or merge.

### Standards

Does the change follow the repository's documented conventions and fit the surrounding design? Also flag meaningful code smells, unnecessary complexity, and opportunities to simplify, but distinguish documented violations from judgment calls. Repository guidance overrides generic taste, and tooling-enforced style does not need human review.

### Spec

Does the change implement the intended behavior completely and correctly? Look for missing or partial requirements, incorrect behavior, and unrequested scope. Tie findings to the source requirement. Skip this axis when no specification exists.

### Engineering Risk

What could make the change fail in practice? Apply engineering judgment to correctness, edge cases, test quality and coverage, security, performance, compatibility, migrations, integration, and operational readiness. Focus on risks that are plausible for this particular change.

## Findings

Every finding should include:

- Severity: Critical, Important, or Minor
- A file and line reference when applicable
- What is wrong and why it matters
- The relevant standard or requirement when applicable
- A suggested direction for fixing it when useful

Do not create findings to fill categories. Mention strengths only when they are specific and useful.

Report under these headings:

1. `## Standards`
2. `## Spec`
3. `## Engineering Risk`
4. `## Merge Readiness`

Keep the three review axes distinct so success in one does not mask failure in another. Cross-reference overlapping findings instead of repeating them. End with a clear `Yes`, `No`, or `With fixes` merge-readiness verdict and a brief reason.

At an implementation checkpoint, evaluate every finding and fix all valid issues before continuing. Reject incorrect findings with evidence, then rerun the relevant checks. When the user requested review only, report the findings and stop.
