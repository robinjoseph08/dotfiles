# Issue tracker: Forgejo

Issues and specs for this repo live as issues on Robin's self-hosted Forgejo, at `https://forgejo.local.rmj.io/<owner>/<repo>`. There is no CLI; use `curl` and `jq` against the Gitea-compatible REST API at `https://forgejo.local.rmj.io/api/v1`. The full reference is `https://forgejo.local.rmj.io/swagger.v1.json`. Forgejo is reachable only from the home network or Tailscale.

## Authentication

The API token lives in the macOS Keychain under service `forgejo-cli`, account `robin`. Read it into a variable inside the same command and never print, log, or write it to a file:

```sh
T=$(security find-generic-password -s forgejo-cli -a robin -w)
API=https://forgejo.local.rmj.io/api/v1/repos/<owner>/<repo>
curl -fsS -H "Authorization: token $T" "$API/issues/1"
```

The token has admin scope. Only delete issues, labels, or anything else when the user asks for that specific action.

## Conventions

- **Create an issue**: `POST $API/issues` with `{"title", "body", "labels": [<label ids>]}`. Creation takes label **IDs**, not names; look them up with `GET $API/labels`. Build the JSON with `jq -n --arg title ... --rawfile body <file>` so multi-line bodies are escaped correctly.
- **Read an issue**: `GET $API/issues/<n>` for the title, body, state, and labels, plus `GET $API/issues/<n>/comments` for the comments.
- **List issues**: `GET "$API/issues?type=issues&state=open&limit=50&labels=<a>,<b>"`, paging with `&page=` until a page comes back empty. Always pass `type=issues`, or pull requests are mixed in.
- **Comment on an issue**: `POST $API/issues/<n>/comments` with `{"body"}`.
- **Apply / remove labels**: `POST $API/issues/<n>/labels` with `{"labels": ["<name>"]}` (names or IDs both work here); `DELETE $API/issues/<n>/labels/<name-or-id>`.
- **Create a missing label**: `POST $API/labels` with `{"name", "color": "#rrggbb"}`.
- **Close**: post the explanation as a comment first, then `PATCH $API/issues/<n>` with `{"state": "closed"}`.
- **Assign**: `PATCH $API/issues/<n>` with `{"assignees": ["robin"]}`.

Infer `<owner>/<repo>` from `git remote -v` (`git@forgejo.local.rmj.io:<owner>/<repo>.git`).

## Scripting

Unlike `gh`, `curl` exits 0 on HTTP errors, so a failed call can pass silently down a script.

- Always use `curl -fsS` so HTTP errors fail the command.
- When a later call uses a value from an earlier response (such as a new issue's `.number`), check it isn't `null` before continuing, and stop on the first failure.
- After publishing several issues, verify titles, bodies, labels, and dependencies with `GET` before reporting success.

## Dependencies

Record every dependency with Forgejo's native issue dependencies, never only as text in the body:

- **Mark issue A as blocked by issue B**: `POST $API/issues/<A>/dependencies` with `{"owner": "<owner>", "repo": "<repo>", "index": <B>}`.
- **Verify**: `GET $API/issues/<A>/dependencies` lists every issue blocking A, with its state. `GET $API/issues/<B>/blocks` lists what B blocks.
- **Remove**: `DELETE $API/issues/<A>/dependencies` with the same body.

A `Blocked by: #<n>` line in the body may supplement the native link but never replace it.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues: list them with `GET "$API/pulls?state=open"`, read the diff with `GET $API/pulls/<n>.diff`, and comment and label through the `issues/<n>` endpoints, since Forgejo shares one number space across issues and PRs.

## When a skill says "publish to the issue tracker"

Create a Forgejo issue with `POST $API/issues`.

## When a skill says "fetch the relevant ticket"

`GET $API/issues/<n>` and `GET $API/issues/<n>/comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body.
- **Child ticket**: the installed Forgejo `15.0.9` API was verified on 2026-10-06 to have no native sub-issues. Add each child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev. After an upgrade, check `/api/v1/version` and `/swagger.v1.json` for native parent-child operations before using them. Dependencies are separate blocking relationships, not a substitute for sub-issues.
- **Blocking**: native issue dependencies, as above. A ticket is unblocked when every issue in `GET $API/issues/<n>/dependencies` is closed.
- **Frontier query**: list the map's open children, drop any with an open dependency or an assignee; first in map order wins.
- **Claim**: assign the ticket to `robin`, the session's first write.
- **Resolve**: comment with the answer, close the ticket, then append a context pointer (gist + link) to the map's Decisions-so-far.
