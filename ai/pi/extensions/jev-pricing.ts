import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    const provider = ctx.modelRegistry.getProvider("typesafe");
    const models = provider?.getAllModels?.() ?? provider?.getModels() ?? [];
    const jev = models.find(model => model.type === "classifier" && model.id === "jev-latest");
    if (!jev || jev.cost.input !== 0) return;

    // Pi 0.81.1's JSON overrides are chat-only. Fill missing Jev 1.13 pricing
    // until the catalog supplies it. Rates are USD per million tokens.
    // Source: https://docs.typesafe.ai/models.md
    pi.registerProvider("typesafe", {
      models: models.map(model => model === jev
        ? { ...model, cost: { input: 0.042, output: 0, cacheRead: 0, cacheWrite: 0 } }
        : model),
    });
  });
}
