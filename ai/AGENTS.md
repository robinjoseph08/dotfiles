## General Conventions

Never use em-dashes for things when it's for something that is meant to be done
by me (READMEs, comments, PR descriptions, etc). I don't use em-dashes, and so
they shouldn't be used.

Never use the AskUserQuestion tool. It doesn't allow for more dynamic responses
which are sometimes necessary when answering questions.

Project instructions go in `AGENTS.md`, not `CLAUDE.md`. Claude Code, Pi, and
Codex all read `AGENTS.md`, but Codex ignores `CLAUDE.md` and Claude Code skips
`AGENTS.md` when a `CLAUDE.md` exists. Never create a `CLAUDE.md` in a repo. If a
repo I own has one, suggest renaming it to `AGENTS.md`.

Shell commands run in zsh (1-indexed arrays, no word splitting). Use zsh idioms
or wrap multi-step scripts in `bash <<'EOF'`.

## GitHub Issue Conventions

### Dependencies

When creating or updating GitHub issues that have dependencies, always record
each dependency using GitHub's native issue dependency API (`POST
/repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by`). A
textual `Blocked by` section may supplement the native relationship, but must
never replace it. Verify the resulting relationships with the corresponding
`GET` endpoint.

## Git Conventions

### Commit Message and PR Title Format

Each commit and PR title should be in the format of `[{Category}] {Change description}`

**Categories** (used for changelog generation):

- `[Frontend]`, `[Backend]`, `[Feature]`, `[Feat]` → Features section
- `[Fix]` → Bug Fixes section
- `[Docs]`, `[Doc]` → Documentation section
- `[Test]`, `[E2E]` → Testing section
- `[CI]`, `[CD]` → CI/CD section
- Any other category → Other section

**Examples:**

```
[Frontend] Add dark mode toggle to settings page
[Backend] Add batch delete endpoint for books
[Fix] Resolve race condition in job worker
[E2E] Add tests for user authentication flow
[CI] Add release automation with GitHub Actions
```

## New Projects

Many tool dependencies aren't installed directly, and instead, are managed
through Mise. Use mise to use exact versions of tools like languages, package
managers, etc.

If you're given the task to write something that is or will become a repo that
will be checked-in, write it in Go. Python can be used for one-off scripts that
won't be committed, but anything real should be done in Go.

When working with Node projects, always prefer pnpm over npm or yarn.
