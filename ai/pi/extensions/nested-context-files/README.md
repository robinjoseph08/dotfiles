# Nested context files

This Pi extension adds Claude Code-style, on-demand loading for context files below Pi's working directory.

When the `read` tool successfully reads a file, the extension walks from the working directory down to that file's parent directory and loads every matching file:

- `AGENTS.md`
- `AGENTS.MD`
- `CLAUDE.md`
- `CLAUDE.MD`

The files are added from broadest to most specific. Their instructions are included in every later model call and are marked as applying only to their containing directory and descendants.

Pi already loads context files in the working directory and its ancestors, so this extension intentionally scans only descendant directories. Canonical paths are checked before loading, so reads and context-file symlinks that resolve outside the working directory are ignored.

Loaded paths are stored as session metadata so they survive resume, compaction, reload, and tree navigation. File contents are read again when restoring a session. A later successful read below an already loaded context file refreshes changed content and removes instructions whose files were deleted, renamed, or became unreadable.

Only the `read` tool triggers discovery. Access through `bash`, `grep`, `find`, or external programs does not.

## Test

```bash
node --test *.test.ts
```
