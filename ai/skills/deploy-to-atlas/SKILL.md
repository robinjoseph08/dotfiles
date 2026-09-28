---
name: deploy-to-atlas
description: Deploy a project to Atlas, Robin's TrueNAS home server, as a private app at https://<name>.local.rmj.io using the `atlas` CLI. Use when the user asks to deploy, host, run, or ship something "on Atlas" or "to the NAS", to set up or edit an atlas.yaml, or to update an app that is already deployed there.
---

# Deploy to Atlas

`atlas deploy` turns a git repo with a Dockerfile into a running TrueNAS app on Atlas. In one command it:

1. Versions the image from git.
2. Builds it for `linux/amd64` and pushes it to the private registry at `forgejo.local.rmj.io`.
3. Creates or updates the TrueNAS app using Robin's app standards, and creates any storage.
4. Waits for the app to be healthy.
5. Adds an Nginx Proxy Manager host so the app is served at `https://<name>.local.rmj.io`.

DNS for `*.local.rmj.io` already points at Atlas.

Everything it deploys is **private to the home network**. Don't manage these apps any other way (`midclt`, SSH, Docker, or the TrueNAS UI), or the next deploy will overwrite the changes.

## Before starting

Check the tooling. The machine setup steps below are the user's to run, since they need their credentials:

- **The CLI:** `atlas --version`. If it's missing, install it:
  `git clone git@forgejo.local.rmj.io:robin/atlas-cli.git ~/code/personal/atlas-cli && cd ~/code/personal/atlas-cli && mise run install:local`
- **Docker Desktop** has to be running.
- **Registry login:** a one-time `docker login forgejo.local.rmj.io -u robin`, using a Forgejo token with package read/write access.
- **Atlas credentials:** a one-time `atlas login truenas` and `atlas login npm --email <atlas NPM user>`. If `atlas deploy` says a credential isn't set, ask the user to run the matching `atlas login` command. They prompt for secrets, so don't run them yourself or ask the user to paste secrets into chat.

## Make the project deployable

The project needs a `Dockerfile` that works under these constraints:

- **Builds for `linux/amd64`.** The Mac is arm64, so use `ARG TARGETOS` / `ARG TARGETARCH` for compiled languages, and never copy in host-built binaries.
- **Runs as an arbitrary user.** Atlas runs every app as uid/gid `568:568`. Only write to mounted volumes or `/tmp`, and don't rely on files owned by a user created in the image.
- **Listens on `0.0.0.0`** at a fixed container port. That's `port` in atlas.yaml.
- **Has `wget`** if atlas.yaml sets `health`, because the generated container health check runs `wget` against it. Alpine and BusyBox images have it. For distroless or scratch images, leave `health` out.
- **Optionally takes `ARG VERSION`.** It receives the git version, e.g. `v0.3.0`, useful for `-ldflags` or a version endpoint.
- **Is pinned.** Use exact base image versions, ideally with digests, and follow the project's existing conventions. Tools are managed with mise (`mise.toml`), not Homebrew or global installs.

A minimal Go example:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM golang:1.27.1-alpine AS build
ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" \
    go build -trimpath -ldflags "-w -s -X main.version=$VERSION" -o /out/app .

FROM alpine:3.24.1
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/app /usr/local/bin/app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/app"]
```

## Deploy a new app

1. **Put the project in git with at least one commit.** Push it to Forgejo, where pushing creates a private repo:
   `git remote add origin git@forgejo.local.rmj.io:robin/<name>.git && git push -u origin master`.
   Follow the repo's commit message conventions. The `forgejo-repos` skill covers SSH setup, existing remotes and troubleshooting.
2. **Run `atlas init`** to create `atlas.yaml`, then edit it (reference below).
3. **Commit `atlas.yaml`.** Deploys refuse to run with uncommitted changes, and that includes untracked files. To release a version, tag it (`git tag v0.1.0`) and push the tag.
4. **Run `atlas deploy --dry-run`.** Show the user the plan: app name, host port, volumes, URL and the generated compose file. Get their go-ahead before the first real deploy, because it creates the app, datasets and proxy host on a shared server.
5. **Run `atlas deploy`.** It prints the URL at the end. The first build can take a few minutes.

To update an app atlas already manages: commit, optionally tag, push, then run `atlas deploy`. A dry run isn't needed unless atlas.yaml changed in a way that affects storage or ports.

## atlas.yaml

```yaml
name: myapp          # lowercase letters, digits, dashes. Also the hostname: myapp.local.rmj.io
port: 8080           # container port. The host port is picked on first deploy and then kept
health: /health      # optional HTTP path returning 2xx. Needs wget in the image
env:                 # optional. Committed to git, so tell the user if you put secrets here
  LOG_LEVEL: info
volumes:             # optional. Container path -> storage
  /data: fast        # /mnt/fast/apps/myapp/data. NVMe, for databases, config and caches
  /blobs: tank       # /mnt/tank/myapp/blobs. HDD pool, for large data
  /media: /mnt/tank/media:ro   # an existing path on Atlas, mounted as-is (":ro" for read-only)
dockerfile: Dockerfile   # optional, relative to atlas.yaml
context: .               # optional Docker build context, relative to atlas.yaml
```

Pick storage by access pattern. SQLite, config and caches go on `fast`. Media and big blobs go on `tank`. Directories atlas creates are owned by `568:568`. Absolute host paths must already exist and must be readable (or writable) by uid 568. Ask the user before mounting their existing data, especially read-write.

## Versions

Image tags come from `git describe --tags`:
- A commit tagged `v1.2.0` deploys `forgejo.local.rmj.io/robin/<name>:1.2.0`.
- Untagged commits get tags like `1.2.0-3-gabc1234`.
- `--allow-dirty` builds uncommitted work with a unique `-dirty-<timestamp>` tag. Use it only for quick experiments the user asked for.

## Rules

- **Only private apps.** Serving something publicly on `<name>.rmj.io` isn't supported by the tool. It needs Cloudflare DNS and a manual NPM change, so ask the user.
- **Don't run `--adopt` without the user's explicit OK.** It replaces the compose config of an existing app that atlas didn't create.
- **Don't delete apps, datasets or proxy hosts.** `atlas` has no delete command on purpose. Ask the user.
- **Keep the name stable.** Renaming `name` deploys a second app instead of renaming the first.

## Troubleshooting

| Error | Fix |
|---|---|
| `... isn't set (run atlas login ...)` | Ask the user to run that login command. |
| `there are uncommitted changes` | Commit, including untracked files, or ask whether `--allow-dirty` is OK. |
| `already exists on Atlas but wasn't deployed by atlas` | An app with that name exists. Pick another name, or ask the user about `--adopt`. |
| `docker buildx build` failed | Check that Docker is running and `docker login forgejo.local.rmj.io` was done, then read the build output. |
| `wasn't healthy after ...` / `crashed` | The container is failing. Check the logs in the TrueNAS UI (Apps, then the app) or with `ssh robin@atlas.local.rmj.io sudo docker logs <name>`. Usual causes are listening on 127.0.0.1, writing to a read-only or root-owned path, or a wrong `port`/`health`. |
| `NPM already has a host for ... that atlas didn't create` | Someone added the proxy host by hand. Tell the user to check that it forwards to the printed host and port. |
| `returned HTTP 502` | NPM can't reach the app. Check `port` matches what the app listens on. |
