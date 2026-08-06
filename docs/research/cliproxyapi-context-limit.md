# Pi + CLIProxyAPI context capacity, usage, and a 272K client cap

## Findings

- **A larger advertised context does not itself consume or charge tokens.** It lets pi retain and send a larger conversation before compacting. OpenAI bills the tokens actually used, with separate input, cached-input, cache-write, and output rates. For GPT-5.6 Sol, requests with **more than 272K input tokens** use 2x input and 1.5x output pricing for the full request. Therefore enabling about 1.05M capacity can increase charges only when requests actually grow larger, especially when they cross 272K. Cached input is discounted, but still counts as input usage and is not free. [OpenAI GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) · [OpenAI pricing](https://developers.openai.com/api/docs/pricing)

- **Pi's `contextWindow` is client metadata used for budgeting and compaction.** Pi auto-compacts when `contextTokens > contextWindow - reserveTokens`; the default reserve is 16,384. Pi also clamps requested output tokens against the same metadata. This describes client behavior, not an upstream enforcement mechanism. [Pi compaction docs](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/compaction.md) · [Pi output-token clamp](https://github.com/earendil-works/pi-mono/blob/main/packages/ai/src/api/simple-options.ts)

- **Pi intentionally defaults direct OpenAI GPT-5.6 to 272K** to remain in the short-context pricing tier. Its custom-model docs say `contextWindow` can be overridden per model and that direct OpenAI defaults to 272K for this reason. The built-in pricing metadata uses `input + cacheRead + cacheWrite` to select a request-wide long-context tier. [Pi custom-model docs](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/models.md) · [Pi cost calculation](https://github.com/earendil-works/pi-mono/blob/main/packages/ai/src/models.ts)

- **To cap the effective pi context for the custom provider `cliproxyapi` or `cpa`, set that provider model's `contextWindow` to `272000` in pi.** If the provider/model is extension-registered, use a `models.json` `modelOverrides` entry for the exact registered provider ID and model ID, for example:

  ```json
  {
    "providers": {
      "cliproxyapi": {
        "modelOverrides": {
          "gpt-5.6-sol": {
            "contextWindow": 272000
          }
        }
      }
    }
  }
  ```

  Replace `cliproxyapi` with `cpa` if that is the actual pi provider ID. With the default reserve, auto-compaction occurs near 255,616 context tokens, leaving response headroom. This is the cleanest way to keep pi from voluntarily building requests beyond the short-context boundary. [Pi per-model overrides](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/models.md) · [Pi compaction docs](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/compaction.md)

- **This pi cap is not a hard upstream limit.** Another client, a custom extension, disabled compaction, estimation error, or a single oversized turn can still submit more, and the upstream remains authoritative. CLIProxyAPI's source likewise labels `max-context-length` as an override of context metadata *advertised to Codex clients*. Its request path separately recognizes upstream `context_length_exceeded`/`context_too_large` responses. That separation shows metadata guides clients while actual rejection is enforced upstream. [CLIProxyAPI config type](https://github.com/router-for-me/CLIProxyAPI/blob/29bdd3c1492c383b89d0be76b353a2891aa04c54/internal/config/config_types.go#L467-L469) · [CLIProxyAPI catalog override](https://github.com/router-for-me/CLIProxyAPI/blob/29bdd3c1492c383b89d0be76b353a2891aa04c54/internal/client/codex/models/models.go#L189-L193) · [CLIProxyAPI upstream overflow handling](https://github.com/router-for-me/CLIProxyAPI/blob/29bdd3c1492c383b89d0be76b353a2891aa04c54/internal/runtime/executor/codex_executor_terminal.go#L273-L279)

- **CLIProxyAPI metadata varies by endpoint/version and should not be confused with the public API capacity.** At the inspected revision, its Codex catalog advertises 372K for `gpt-5.6-sol`, while OpenAI's public API docs state 1.05M. In either case, changing advertised metadata changes client budgeting, not the number of tokens billed or a guaranteed server-side limit. [CLIProxyAPI Codex catalog](https://github.com/router-for-me/CLIProxyAPI/blob/29bdd3c1492c383b89d0be76b353a2891aa04c54/internal/registry/models/codex_client_models.json#L4-L25) · [OpenAI model capacity](https://developers.openai.com/api/docs/models/gpt-5.6-sol)

## Bottom line

Allowing 1.05M increases possible usage, not automatic usage. Cap pi's custom-provider model metadata at `272000` so compaction happens before long-context requests. Treat that as a client-side spending guardrail, not upstream enforcement, and monitor actual `input`, `cacheRead`, `cacheWrite`, and output usage.
