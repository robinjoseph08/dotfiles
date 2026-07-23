# Inline skills

Adds skill completion and expansion throughout a Pi prompt.

## Usage

Type a skill command after whitespace, then press Tab to open the completion menu:

```text
Review this with /skill:code-re<Tab> and then summarize the findings.
```

Pi reserves `/` as a natural autocomplete trigger for prompt-start commands, so the inline menu does not open automatically while typing. Inline completion is explicitly triggered with Tab.

Multiple skill invocations can appear in one prompt. Each invocation is replaced with the same `<skill>` block Pi uses for a prompt-start skill command.

Prompt-start invocations are left to Pi's native implementation:

```text
/skill:code-review review this branch
```

To mention an invocation without expanding it, escape the slash:

```text
Mention \/skill:code-review literally.
```

Run `/reload` after changing the extension.
