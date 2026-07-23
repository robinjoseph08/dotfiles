# History search

Adds Claude Code-style reverse prompt history search to Pi.

## Controls

- `Ctrl+R`: Open history search. While searching, move to an older match.
- `Ctrl+S`: Cycle scope through `everywhere`, `project`, and `session`.
- `Up`: Move to a newer match.
- `Down`: Move to an older match.
- `Enter`: Put the selected prompt into the editor.
- `Escape` or `Ctrl+C`: Cancel.

The current editor text becomes the initial search query. Search is case-insensitive and results are ordered newest first.

## Scopes

- `everywhere`: Prompts from every discovered Pi session.
- `project`: Prompts from sessions whose working directory matches the current working directory.
- `session`: Prompts from the current session only.

Expanded skill blocks are collapsed back to `/skill:name` when possible.

## Keybinding note

Pi normally uses `Ctrl+R` to rename a session inside `/resume`. The global keybindings file moves that action to `Shift+R` so history search can own `Ctrl+R` without a startup conflict warning:

```json
{
  "app.session.rename": "shift+r"
}
```

Run `/reload` after changing the extension or keybindings.
