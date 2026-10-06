# Issue tracker: Forgejo

Issues and specs for this repo live at `https://forgejo.local.rmj.io/<owner>/<repo>`. Use Forgejo CLI `fj` for ordinary operations. The commands below match `fj` 0.6.0 and Forgejo 15.0.9. Forgejo is reachable only from the home network or Tailscale.

## Access and targeting

Check `fj version` and `fj -H forgejo.local.rmj.io whoami`. If the CLI is missing or authentication fails, stop and tell the user; do not install it or change login configuration without approval. `fj` uses its own saved login, separate from the Keychain token used for REST below. Never print stored credentials.

Infer `<owner>/<repo>` from the Forgejo git remote, then pass it explicitly. Use `--repo <owner>/<repo>` for create/search commands and quote issue identifiers as `'<owner>/<repo>#<n>'`. `-R` selects a local remote, not an owner/repo. Explicit host and repo arguments prevent accidental targeting of another remote.

## Conventions

Prefix every command below with `fj -H forgejo.local.rmj.io`:

| Task | Command |
|---|---|
| Create an issue | `issue create "<title>" --repo <owner>/<repo> --body-file <file> --no-template` |
| Read an issue | `issue view '<owner>/<repo>#<n>'`, then `issue view '<owner>/<repo>#<n>' comments` |
| Read assignees | `issue view '<owner>/<repo>#<n>' assignees` |
| List open issues | `issue search --repo <owner>/<repo> --state open`, optionally `--labels "<label>"` |
| Comment | `issue comment '<owner>/<repo>#<n>' --body-file <file>` |
| Add/remove labels | `issue edit '<owner>/<repo>#<n>' labels --add "<label>" --rm "<other-label>"`; omit unused options |
| Create a missing label | `repo labels <owner>/<repo> create "<label>" "<rrggbb>"` |
| Close with an explanation | `issue close '<owner>/<repo>#<n>' --with-msg "<reason>"`; comments before closing |
| Assign | `issue assign '<owner>/<repo>#<n>' robin` |

Search fetches all pages and excludes PRs. Supply body files or text explicitly to avoid opening an editor. Creation has no label or assignee flags; apply them afterwards. If blank issues are disabled, select an approved `--template` instead of `--no-template`. `--body` cannot be combined with `--template`. For a YAML template, `--body-file` must contain the form structure that `fj` expects, not an arbitrary issue body. If that form cannot be prepared from the selected template, stop and ask for guidance rather than opening an editor or bypassing the requirement.

When a skill says "publish to the issue tracker", create an issue and apply the configured labels. When it says "fetch the relevant ticket", read the issue and its comments.

## Automation and verification

`fj` 0.6.0 has no JSON output or generic API command. Use REST plus `jq` when a script needs structured responses, issue numbers from creation, bulk verification, or dependencies. Do not parse localized CLI output for identifiers. Unknown label names can warn without failing the command, so verify resulting labels through REST before reporting success.

After publishing, verify titles, bodies, labels, and native dependencies with GET requests. Stop on any failed call or missing identifier. Preserve existing labels. Only delete issues, labels, or other resources when the user asks for that specific action.

## REST fallback and dependencies

The fallback token lives in the macOS Keychain under service `forgejo-cli`, account `robin`. It is not the CLI's login. If missing, stop and tell the user. Read it into a variable inside the same command; never print, log, or write it to a file:

```sh
T=$(security find-generic-password -s forgejo-cli -a robin -w) || exit
API="https://forgejo.local.rmj.io/api/v1/repos/<owner>/<repo>"
curl -fsS -H "Authorization: token $T" "$API/issues/<n>"
```

Always use `curl -fsS` so HTTP errors fail. Build JSON with `jq -n` and `--rawfile` rather than interpolating bodies. For structured issue creation, `POST $API/issues` with `{"title","body","labels":[<numeric-label-ids>]}`; resolve label IDs with `GET $API/labels` and use the response's `.number` for later issue operations. Page through list endpoints with `limit` and `page` until empty. The installed API reference is `https://forgejo.local.rmj.io/swagger.v1.json`.

`fj` has no dependency commands. Record each dependency natively, never only as body text:

- **Make A depend on B**: `POST $API/issues/<A>/dependencies` with `{"owner":"<owner>","repo":"<repo>","index":<B>}`. Both A and B are repository-local issue numbers, not global IDs.
- **Verify**: `GET $API/issues/<A>/dependencies` lists A's blockers; `GET $API/issues/<B>/blocks` lists the issues B blocks. Read all pages and verify the expected issue numbers and states.
- **Remove**: `DELETE $API/issues/<A>/dependencies` with the same body, only when the user approves removing that relationship.

A `Blocked by: #<n>` line may supplement native links, never replace them. The fallback token has admin scope; do not use that scope to perform unrequested destructive or instance-wide changes.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When enabled, use `pr search --repo <owner>/<repo> --state open`, `pr view '<owner>/<repo>#<n>'`, `pr view '<owner>/<repo>#<n>' comments`, and `pr view '<owner>/<repo>#<n>' diff`, each with the same CLI prefix above. Use `pr comment` and `pr edit ... labels` for comments and labels. Apply the repo's definition of an external contributor rather than treating every returned PR as external; use REST when author or membership data is needed. Issues and PRs share one number space.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body, with linked child issues as tickets.

- **Child ticket**: Forgejo 15.0.9 has no native sub-issues. Add each child to a task list in the map body and put `Part of #<map>` at the top of the child body. Use labels `wayfinder:<type>` for `research`/`prototype`/`grilling`/`task`. After a server upgrade, check `/api/v1/version` and Swagger before adopting parent-child operations. Installing a newer CLI does not add server support.
- **Blocking**: use the native dependency operations above. A ticket is unblocked only when all its blockers are closed; parent links are not blocking edges.
- **Frontier**: list the map's open children, read their native dependencies and assignees, then drop any with an open blocker or assignee. First in map order wins.
- **Claim**: assign the ticket to `robin` as the session's first write.
- **Resolve**: comment with the answer, close the ticket, and append a context pointer with a gist and link to the map's Decisions-so-far.
