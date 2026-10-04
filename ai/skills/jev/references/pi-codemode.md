# Jev through Pi codemode

Read this reference only when running in Pi with the `codemode` tool available. Other harnesses should use the shell helpers in SKILL.md. A generic JavaScript execution tool is not necessarily Pi codemode.

Codemode calls classifiers through Pi's configured providers and credentials. It can fetch data with tools, classify items, and return only useful results without sending every intermediate response to the main agent. The classification itself still sends the supplied state and questions to the provider. Obtain approval for private content before making those calls, as required by SKILL.md.

## Find a model

Use `models.getAvailableOfType("classifier")` to discover classifiers with usable credentials. Prefer `{ provider: "typesafe", id: "jev-latest" }` when available. Otherwise choose an available Jev entry, respecting the user's provider preference. Do not guess another provider's model ID.

If none is available, use the shell helpers if their separate credentials are available. Otherwise report what is missing without printing secrets. Do not silently resend failed native requests through the helpers.

## Classify

The codemode input is JavaScript source, not a JSON wrapper or a markdown fence. This example uses made-up, public-safe content:

```js
const available = await models.getAvailableOfType("classifier");
const jev = available.find(m => m.provider === "typesafe" && m.id === "jev-latest");
if (!jev) return { error: "The configured TypeSafe Jev classifier is unavailable." };

const result = await models.classify(jev, {
  state: { message: "The change works, thanks." },
  questions: {
    approved: {
      type: "bool",
      instructions: "Does `message` express approval of the result?",
      criteria: {
        true: "Expresses approval",
        false: "Does not express approval"
      }
    }
  }
});
if (result.stopReason !== "stop") {
  return { error: result.errorMessage ?? result.stopReason };
}
return { answers: result.answers, usage: result.usage };
```

For a batch, make one `models.classify()` call per item with all its questions. Use `Promise.all()` to submit the batch; Pi runs at most four model calls at once per script and queues the rest. Keep each item's ID with its result. Check `stopReason` for every result so errors cannot disappear during filtering.

Return the selected items, borderline items for your own review, errors, and usage totals. Do not return the entire input pile unless needed. Only explicit script output reaches the main agent. Use tools to save full results to a file when the task needs a complete record.

## API differences

Keep the question-writing and uncertainty guidance from SKILL.md, but adapt the direct API examples:

| Direct TypeSafe API | Pi classifier API |
| --- | --- |
| Question `type: "noul"` | Question `type: "bool"` |
| Optional yes/no criteria | Supply `criteria: { true: "...", false: "..." }` |
| Answer `noul` | Answer `probability` |
| Choice criteria can include null or objects | Use string descriptions for each choice |
| Score answer includes per-level probabilities | Documented score answer contains `score` and `confidence`, without per-level probabilities |

Choice answers contain `choice`, `probabilities`, and `confidence`. Score answers contain `score` and `confidence`. Boolean answers contain `probability` without a confidence field. Apply the skill's Noul thresholds to Pi's boolean probability.

Provider errors normally return `stopReason: "error"` with `errorMessage`, rather than throwing. Report the returned error verbatim; do not invent an HTTP status or body that Pi did not expose.

Pi adds classifier usage to session accounting. When direct TypeSafe catalog pricing is absent, Pi may record zero cost despite billable usage. Report the actual cost as unknown unless you have verified pricing; label any calculation as an estimate.
