---
name: forgejo-repos
description: Host git repos privately on Robin's self-hosted Forgejo at forgejo.local.rmj.io, instead of GitHub. Use when the user asks to push, back up, store, or clone a repo "on Forgejo", "privately", or "on Atlas", wants a private remote for a project that shouldn't be public, or wants CI (Forgejo Actions workflows) for a repo hosted there.
---

# Private repos on Forgejo

Forgejo runs on Atlas at `https://forgejo.local.rmj.io`. It's reachable only from the home network (and Tailscale), and every repo is private. Pushing a repo there does **not** deploy it. For deploys, use the `deploy-to-atlas` skill. That skill also expects the code to be pushed here.

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
3. **Use `master` as the branch.** Every repo uses `master`, never `main`. If the current branch is `main` (or a fresh `git init` left it unborn under another name), rename it first with `git branch -m master`, or `git symbolic-ref HEAD refs/heads/master` before the first commit.
4. **Look at what will be pushed.** Make sure there's at least one commit, follow the repo's commit message conventions, and check `.gitignore` covers build output, `.env` files and other secrets. The repo is private, but it still shouldn't hold secrets.
5. **Push:**
   ```sh
   git remote add origin git@forgejo.local.rmj.io:robin/<repo>.git
   git push -u origin master --tags
   ```
   Pushing to a name that doesn't exist yet creates the repo, and it comes out private. Don't create it in the web UI first. The first branch pushed becomes the default branch.
6. **Confirm:** `git status -sb` shows the branch tracking `origin/master`. The repo is at `https://forgejo.local.rmj.io/robin/<repo>`.

To clone an existing repo: `git clone git@forgejo.local.rmj.io:robin/<repo>.git`.

## CI (Forgejo Actions)

Forgejo Actions runs workflows from `.forgejo/workflows/*.yml` (and `.github/workflows/` when there's no `.forgejo` directory). The syntax is GitHub Actions syntax. One runner named `Atlas` serves every repo:

- **Use `runs-on: ubuntu-latest`.** That's the only label. It runs jobs in `ghcr.io/catthehacker/ubuntu:act-24.04-<date>`, which has git, node, and the docker CLI. Any other `runs-on` value sits in the queue forever.
- **Resolving `uses:`.** Short names like `actions/checkout@v4` or `actions/cache@v4` resolve against `data.forgejo.org`, which mirrors the common actions. For anything else, write the full URL: `uses: https://github.com/<owner>/<action>@<ref>`.
- **Docker works.** `docker build` and `docker run` go to a Docker-in-Docker daemon, isolated from the apps on Atlas.
- **Registry pushes need `REGISTRY_TOKEN`.** The automatic `GITHUB_TOKEN`/`FORGEJO_TOKEN` gets a 401 from the container registry. `REGISTRY_TOKEN` is a user-level Actions secret already set on `robin` (a token with package read/write), so every repo can use it:
  ```yaml
  - run: |
      echo "${{ secrets.REGISTRY_TOKEN }}" | docker login forgejo.local.rmj.io -u robin --password-stdin
      docker push forgejo.local.rmj.io/robin/<app>:<tag>
  ```
- **GitHub API calls need `MISE_GITHUB_TOKEN`.** The runner puts Forgejo's job token in `GITHUB_TOKEN`, and a workflow can't override it. Tools that call GitHub's API with it, like mise looking up `github:` tools, get a 401. `MISE_GITHUB_TOKEN` is a user-level Actions secret already set on `robin` (a fine-grained GitHub token with read-only access to public repos). Pass it to `jdx/mise-action`, and mise prefers it over `GITHUB_TOKEN`:
  ```yaml
  - uses: https://github.com/jdx/mise-action@<ref>
    with:
      install: true
      github_token: ${{ secrets.MISE_GITHUB_TOKEN }}
  ```
  For other tools that read `GITHUB_TOKEN`, set their own token variable from the secret, or run them with `env -u GITHUB_TOKEN` to go anonymous.
- **pnpm puts its store inside the checkout.** The checkout is its own mount, and pnpm keeps its store on the project's filesystem, so `pnpm install` creates `.pnpm-store/` at the repo root. Anything that scans the tree then trips over thousands of store files: `prettier --check .` fails with "Code style issues found", and ESLint or broad globs can too. Add `.pnpm-store/` to `.gitignore` (Prettier honors it), ESLint's ignores, and `.dockerignore`. It never shows up locally, where the store lives in the home directory.
- **Limits.** At most 2 jobs run at once, and a job is cut off after 1 hour.
- **Hostnames.** `*.local.rmj.io` names resolve inside jobs.

To check a run, use the API (see below): `GET /repos/robin/<repo>/actions/tasks` lists each job with its status (`success`, `failure`, `running`, ...). `GET /repos/robin/<repo>/actions/runs` lists workflow runs. If a job fails, retrieve its logs using the instructions below rather than asking the user to paste output from the browser.

To reproduce a run locally with the same runner, run `forgejo-runner exec` from the runner's image against a fresh `git init` copy of the repo (a worktree's `.git` file doesn't resolve inside the container):

```sh
docker run --rm --user root -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD":"$PWD" -w "$PWD" \
  code.forgejo.org/forgejo/runner:<runner version> forgejo-runner exec \
  -W .forgejo/workflows/ci.yml -j <job> -E workflow_dispatch -i ghcr.io/catthehacker/ubuntu:act-24.04 \
  -s GITHUB_TOKEN=bogus
```

`GET /admin/actions/runners` shows the runner's version. A local run skips `actions/checkout` and copies the directory instead, and `-s GITHUB_TOKEN=bogus` stands in for the job token GitHub rejects. If the workflow installs `github:` tools with mise, also pass `-s MISE_GITHUB_TOKEN="$(gh auth token)"`, or mise install fails with a 401 that the real run doesn't have. Passing the token on the command line keeps it out of files.

The runner itself is the `forgejo-runner` app on Atlas. Changing it (labels, capacity, image versions) is an Atlas change, so check with the user first.

### Get CI job logs

Atlas was verified running Forgejo **15.0.9** on 2026-10-05. This version has no REST log-download endpoints, regardless of token permissions. Read stored logs over SSH instead. After an upgrade, check `GET /api/v1/version` and the installed Swagger definition before choosing the method.

#### Forgejo 15: read logs on Atlas

The host has `sqlite3` and `zstd`. The database is `/mnt/fast/apps/forgejo/data/data/gitea.db`, and compressed logs are under `/mnt/fast/apps/forgejo/data/actions_log/`.

1. Get the workflow run's global `id` from `GET /repos/robin/<repo>/actions/runs`. This is not the repository-local number in the browser URL, which is `index_in_repo`.
2. Query the task metadata read-only. This example uses global run ID `19`; replace it with the selected run's ID:

   ```sh
   ssh robin@atlas.local.rmj.io 'sudo sqlite3 -readonly -header -column /mnt/fast/apps/forgejo/data/data/gitea.db "
   SELECT j.run_id, j.id AS job_id, j.name, t.id AS task_id, t.attempt,
          t.log_in_storage, t.log_expired, t.log_filename
   FROM action_task AS t
   JOIN action_run_job AS j ON j.id = t.job_id
   WHERE j.run_id = 19
   ORDER BY j.id, t.attempt DESC;"'
   ```

3. Pick the desired job and attempt, normally the latest. Use its exact `log_filename` relative to the log directory. For example:

   ```sh
   ssh robin@atlas.local.rmj.io \
     'sudo zstd -dc /mnt/fast/apps/forgejo/data/actions_log/robin/camera-cli/13/19.log.zst'
   ```

Do not guess filenames from run or job IDs. Task IDs differ from job IDs on retries. `log_expired = 1` means the log has expired; `log_in_storage = 0` means it is not finalized in this storage yet. The stored-log method is for finalized logs, not live streaming. For live output, use the signed-in web UI at `https://forgejo.local.rmj.io/robin/<repo>/actions/runs/<index_in_repo>`.

This is an internal-storage workaround, not a stable API. Keep database access read-only and select only the needed metadata, since other columns contain credentials. Logs can contain secrets too; show only relevant output and redact sensitive values. Do not modify the database or log files.

#### Forgejo 16+: use the REST API

[PR #12666](https://codeberg.org/forgejo/forgejo/pulls/12666) added log downloads in Forgejo 16.0.0. Prefer these endpoints when the installed version supports them:

- `GET /api/v1/repos/{owner}/{repo}/actions/jobs/{job_id}/logs`: plaintext, latest attempt by default. Use `?attempt=N` for a particular attempt.
- `GET /api/v1/repos/{owner}/{repo}/actions/runs/{run_id}/logs`: ZIP containing each job's latest attempt.

Use global API run/job IDs, not the repository-local run number or task ID. A PAT needs `read:repository`, access to the selected repository, and Actions read permission. Use the Keychain token described below:

```sh
T=$(security find-generic-password -s forgejo-cli -a robin -w) || exit
curl -fsS -H "Authorization: token $T" \
  "https://forgejo.local.rmj.io/api/v1/repos/robin/<repo>/actions/jobs/<job_id>/logs"
```

Do not upgrade the instance just to retrieve logs without the user's approval.

## What Forgejo here doesn't do

- **No Git LFS.** It's turned off, so don't set up LFS tracking. Large binaries don't belong in these repos. If a project needs them, ask the user where they should live on Atlas.
- **Push creates repos only under `robin`.** Organizations would have to be made in the web UI by the user.

## API access

An admin API token for `robin` is stored in the macOS Keychain under service `forgejo-cli`, account `robin`. Use it for anything the web UI would otherwise be needed for: issues, labels, issue dependencies, pull requests, and repo settings such as the description or default branch.

Read it into a variable inside the same command and never print it, log it, or write it to a file:

```sh
T=$(security find-generic-password -s forgejo-cli -a robin -w)
curl -fsS -H "Authorization: token $T" https://forgejo.local.rmj.io/api/v1/user
```

The API is Gitea-compatible and lives at `https://forgejo.local.rmj.io/api/v1`. The full reference is `https://forgejo.local.rmj.io/swagger.v1.json`. Common calls:

| Task | Call |
|---|---|
| Create an issue | `POST /repos/robin/<repo>/issues` with `{"title", "body", "labels": [<label ids>]}` |
| Create a label | `POST /repos/robin/<repo>/labels` with `{"name", "color"}` |
| Mark issue A as blocked by issue B | `POST /repos/robin/<repo>/issues/<A>/dependencies` with `{"owner": "robin", "repo": "<repo>", "index": <B>}` |
| List what blocks issue A | `GET /repos/robin/<repo>/issues/<A>/dependencies` |
| Change repo settings | `PATCH /repos/robin/<repo>` with e.g. `{"default_branch": "master"}` |
| List a repo's CI jobs | `GET /repos/robin/<repo>/actions/tasks` |
| Run a workflow manually | `POST /repos/robin/<repo>/actions/workflows/<file>.yml/dispatches` with `{"ref": "master"}` (the workflow needs `on: workflow_dispatch`) |
| List container images | `GET /packages/robin?type=container` (one entry per tag and per manifest digest) |
| Delete an image version | `DELETE /packages/robin/container/<name>/<tag or sha256:digest>` |

Record issue dependencies with the dependencies endpoint, not only as text in the body, and verify them with the matching `GET`.

The token has admin scope, so it can also delete repos, rewrite settings, and manage users. Only do destructive or instance-wide things (deleting repos, branches, issues, or packages, changing visibility, anything under `/admin`) when the user asks for that specific action. Never force-push over someone else's history without being asked.

If the Keychain entry is missing, for example on a new machine, stop and tell the user. They create the token in Forgejo under Settings → Applications and store it with `security add-generic-password -s forgejo-cli -a robin -w`.

## Troubleshooting

| Error | Fix |
|---|---|
| `Permission denied (publickey)` | The SSH key or config is missing on this machine. Tell the user. |
| `Connection refused` or timeout | You're off the home network or Tailscale, or Atlas is down. Tell the user. |
| `rejected ... (fetch first)` | Someone pushed in the meantime. Pull and rebase or merge, then push again. Never force-push to fix it without asking. |
| `Forgejo: Unable to access repository path` | Happened once on the very first push to a brand-new instance, and a retry fixed it. If it happens again, tell the user. |
