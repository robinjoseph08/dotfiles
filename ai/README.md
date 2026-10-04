# AI configuration

Portable configuration for Claude Code, Pi, Codex, and other agents lives here.

## Managed configuration

- `AGENTS.md` holds the global instructions shared by every agent. It is linked to `~/.claude/CLAUDE.md`, `~/.pi/agent/AGENTS.md`, and `~/.codex/AGENTS.md`. Claude Code only reads `AGENTS.md` as a project file, so the `CLAUDE.md` link is its user-level entry point.
- `skills/` is the canonical skill collection. The whole directory is linked to both `~/.agents/skills/` and `~/.claude/skills/`, so skills installed through either location appear in this repository. Codex discovers the user-level skills from `~/.agents/skills/` directly.
- `claude/` contains Claude Code settings, commands, and the status line.
- `pi/` contains Pi-only instructions (`APPEND_SYSTEM.md`, appended to Pi's system prompt), settings, model overrides, keybindings, extensions, and themes. The entire extensions directory is linked so newly created extensions are immediately tracked by this repository. Settings and model overrides are also symlinked, so edits made by Pi or by hand update the repository copies. This includes generated fields in settings, such as `lastChangelogVersion`.

Run `./scripts/setup-ai.sh` to install only the AI configuration, or run `./setup.sh` for the full machine setup.

Run `./scripts/test-pi-extensions.sh` to execute all Pi extension tests using the dependencies bundled with the installed Pi package.

Existing files and managed directories are moved under `old/ai/` before they are replaced. Before replacing an existing skills directory, setup imports locally installed skills that do not conflict with canonical names. The skills and Pi extensions directories are fully owned by this repository. Unmanaged themes are left in place because setup links those repository entries individually.

## Intentionally local

Credentials and generated state must not be committed. This includes:

- Pi `auth.json`, sessions, trust decisions, package caches, and generated model catalog state
- Claude history, projects, sessions, caches, backups, and plugin caches
- Shared skill manager `.skill-lock.json` state
- Codex authentication, history, sessions, caches, logs, project trust, and command approval rules

Pi installs the packages declared in `pi/settings.json` on startup. Claude Code installs enabled plugins through its own plugin manager. API logins still need to be completed separately on each machine.
