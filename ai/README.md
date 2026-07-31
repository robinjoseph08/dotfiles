# AI configuration

Portable configuration for Claude Code, Pi, Codex, and other agents lives here.

## Managed configuration

- `CLAUDE.md` is linked to both `~/.claude/CLAUDE.md` and `~/AGENTS.md`.
- `skills/` is the canonical skill collection. The whole directory is linked to both `~/.agents/skills/` and `~/.claude/skills/`, so skills installed through either location appear in this repository. Codex discovers the user-level skills from `~/.agents/skills/` directly.
- `claude/` contains Claude Code settings, commands, and the status line.
- `pi/` contains Pi instructions, settings, keybindings, extensions, and themes. The entire extensions directory is linked so newly created extensions are immediately tracked by this repository. Managed settings are merged into Pi's local settings so Pi can keep writable state out of this repository.

Run `./scripts/setup-ai.sh` to install only the AI configuration, or run `./setup.sh` for the full machine setup.

Existing files and managed directories are moved under `old/ai/` before they are replaced. Before replacing an existing skills directory, setup imports locally installed skills that do not conflict with canonical names. The skills and Pi extensions directories are fully owned by this repository. Unmanaged themes are left in place because setup links those repository entries individually.

## Intentionally local

Credentials and generated state must not be committed. This includes:

- Pi `auth.json`, sessions, trust decisions, package caches, and generated changelog version state
- Claude history, projects, sessions, caches, backups, and plugin caches
- Shared skill manager `.skill-lock.json` state
- Codex authentication, history, sessions, caches, logs, project trust, and command approval rules

Pi installs the packages declared in `pi/settings.json` on startup. Claude Code installs enabled plugins through its own plugin manager. API logins still need to be completed separately on each machine.
