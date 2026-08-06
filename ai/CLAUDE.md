## General Conventions

Never use em-dashes for things when it's for something that is meant to be done by me (READMEs, comments, PR descriptions, etc). I don't use em-dashes, and so they shouldn't be used.

Never use the AskUserQuestion tool. It doesn't allow for more dynamic responses which are sometimes necessary when answering questions.

## GitHub Issue Conventions

### Dependencies

When creating or updating GitHub issues that have dependencies, always record each dependency using GitHub's native issue dependency API (`POST /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by`). A textual `Blocked by` section may supplement the native relationship, but must never replace it. Verify the resulting relationships with the corresponding `GET` endpoint.

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
