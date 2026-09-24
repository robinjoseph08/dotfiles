---
name: forgejo-repos
description: Host git repos privately on Robin's self-hosted Forgejo at forgejo.local.rmj.io, instead of GitHub. Use when the user asks to push, back up, store, or clone a repo "on Forgejo", "privately", or "on Atlas", or wants a private remote for a project that shouldn't be public.
---

# Private repos on Forgejo

Forgejo runs on Atlas at `https://forgejo.local.rmj.io`. It's reachable only from the home network (and Tailscale), and every repo is private. It's plain git hosting: pushing a repo there does **not** deploy it. For deploys, use the `deploy-to-atlas` skill. That skill also expects the code to be pushed here.

Everything lives under the user `robin`: `git@forgejo.local.rmj.io:robin/<repo>.git`.

## Check access

Run `ssh -T forgejo.local.rmj.io`. It should say `Hi there, robin! You've successfully authenticated`. It works through this `~/.ssh/config` entry:

```
Host forgejo.local.rmj.io
  Port 2222
  User git
  IdentityFile ~/.ssh/forgejo_ed25519
```

If the entry or the key is missing, for example on a new machine, stop and tell the user. The key has to be added in Forgejo under Settings → SSH / GPG Keys, and only the user can do that.

## Push a repo

1. **Pick the repo name.** Match the project directory, in lowercase with dashes (e.g. `anki-notifier`).
2. **Check the existing remotes** with `git remote -v`:
   - **No remote:** add Forgejo as `origin`.
   - **Already on GitHub or elsewhere:** ask the user whether Forgejo should replace `origin` or be added alongside it. If alongside, name the extra remote `forgejo`. Never remove or rename an existing remote without asking.
3. **Look at what will be pushed.** Make sure there's at least one commit, follow the repo's commit message conventions, and check `.gitignore` covers build output, `.env` files and other secrets. The repo is private, but it still shouldn't hold secrets.
4. **Push:**
   ```sh
   git remote add origin git@forgejo.local.rmj.io:robin/<repo>.git
   git push -u origin main --tags
   ```
   Pushing to a name that doesn't exist yet creates the repo, and it comes out private. Don't create it in the web UI first. Use the repo's actual default branch if it isn't `main`.
5. **Confirm:** `git status -sb` shows the branch tracking `origin/main`. The repo is at `https://forgejo.local.rmj.io/robin/<repo>`.

To clone an existing repo: `git clone git@forgejo.local.rmj.io:robin/<repo>.git`.

## What Forgejo here doesn't do

- **No CI.** There are no Actions runners, so `.forgejo/workflows` and `.github/workflows` files never run. Run checks locally, e.g. `mise check`.
- **No Git LFS.** It's turned off, so don't set up LFS tracking. Large binaries don't belong in these repos. If a project needs them, ask the user where they should live on Atlas.
- **Push creates repos only under `robin`.** Organizations would have to be made in the web UI by the user.
- **Agents have no API token.** Repo settings (description, visibility, renaming, deleting) and issues or pull requests go through the web UI, so ask the user. Never delete a repo or force-push over someone else's history without being asked.

## Troubleshooting

| Error | Fix |
|---|---|
| `Permission denied (publickey)` | The SSH key or config is missing on this machine. Tell the user. |
| `Connection refused` or timeout | You're off the home network or Tailscale, or Atlas is down. Tell the user. |
| `rejected ... (fetch first)` | Someone pushed in the meantime. Pull and rebase or merge, then push again. Never force-push to fix it without asking. |
| `Forgejo: Unable to access repository path` | Happened once on the very first push to a brand-new instance, and a retry fixed it. If it happens again, tell the user. |
