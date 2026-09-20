# Skill mechanics

The skill-specific branch of [`writing-for-agents`](SKILL.md): what changes when the document is a skill (frontmatter, the invocation choice, and router skills). Everything else about writing it is the universal reference in `SKILL.md`.

## Invocation

Two choices, trading the two loads:

- A **model-invoked** skill is available for automatic discovery because `disable-model-invocation` is absent or false. Its `description` stays in the agent's context as a trigger, so the model can select it without an explicit path. The human can still invoke it directly. This discoverability creates permanent context load. Write a model-facing description carrying the trigger branches; the pointer-writing rules in `SKILL.md` apply in full.
- A **user-invoked** skill is hidden from automatic discovery with `disable-model-invocation: true`. Its `description` becomes a human-facing one-line summary. A human can invoke it directly, and another skill can reach it through an explicit context pointer to its file. It avoids automatic-discovery context load but spends cognitive load because the human or referring skill must know it exists.

Pick model-invocation only when the agent should discover the skill automatically. If a human will select it, or another skill can name its path explicitly, make it user-invoked.

Shared reference that does not need automatic discovery can live in a user-invoked skill reached through an explicit pointer, or in a plain file outside the skill system when it does not need its own invocation command.

## Splitting by invocation

The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a model-invoked skill when you have a distinct leading word that should trigger automatic discovery on its own, using a trigger word that appears in real prompts. You pay context load for the new always-loaded description, so that independent discovery has to be worth it.

## Router skills

When user-invoked skills multiply past what you can remember, that piled-up cognitive load is cured by a **router skill**: one user-invoked skill that names the others and when to reach for each, so the human has one skill to remember instead of many. The router may direct the agent through explicit context pointers even though those skills are absent from automatic discovery.
