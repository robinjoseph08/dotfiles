import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  calculateCost,
  type Api,
  type Model,
  type ModelCost,
  type Usage,
} from "@earendil-works/pi-ai";

function finite(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, value) : 0;
}

function normalizedUsage(value: unknown): Usage | undefined {
  if (!value || typeof value !== "object") return undefined;
  const usage = value as Partial<Usage>;
  const cost = usage.cost && typeof usage.cost === "object" ? usage.cost : undefined;
  const input = finite(usage.input);
  const output = finite(usage.output);
  const cacheRead = finite(usage.cacheRead);
  const cacheWrite = finite(usage.cacheWrite);

  return {
    input,
    output,
    cacheRead,
    cacheWrite,
    cacheWrite1h: Math.min(cacheWrite, finite(usage.cacheWrite1h)),
    reasoning: typeof usage.reasoning === "number" ? finite(usage.reasoning) : undefined,
    totalTokens: finite(usage.totalTokens) || input + output + cacheRead + cacheWrite,
    cost: {
      input: finite(cost?.input),
      output: finite(cost?.output),
      cacheRead: finite(cost?.cacheRead),
      cacheWrite: finite(cost?.cacheWrite),
      total: finite(cost?.total),
    },
  };
}

export function hasNonzeroPricing(cost: ModelCost | undefined): cost is ModelCost {
  if (!cost) return false;
  const rates = [cost, ...(cost.tiers ?? [])];
  return rates.some((rate) =>
    [rate.input, rate.output, rate.cacheRead, rate.cacheWrite].some(
      (value) => Number.isFinite(value) && value > 0,
    ),
  );
}

export function formatSessionCost(cost: number): string {
  if (!Number.isFinite(cost) || cost <= 0) return "$0.000";
  if (cost < 0.001) return `$${cost.toPrecision(3)}`;
  return `$${cost.toFixed(3)}`;
}

export function calculateUsageCost(usageValue: unknown, model?: Model<Api>): number {
  const usage = normalizedUsage(usageValue);
  if (!usage) return 0;
  if (usage.cost.total > 0 || !model || !hasNonzeroPricing(model.cost)) return usage.cost.total;
  return calculateCost(model, usage).total;
}

function pricedModel(
  ctx: ExtensionContext,
  provider: string | undefined,
  modelIds: Array<string | undefined>,
): Model<Api> | undefined {
  const ids = [...new Set(modelIds.filter((id): id is string => typeof id === "string" && id.length > 0))];

  for (const modelId of ids) {
    const exact = provider ? ctx.modelRegistry.find(provider, modelId) : undefined;
    if (exact && hasNonzeroPricing(exact.cost)) return exact;

    if (provider === "cpa") {
      const upstream =
        ctx.modelRegistry.find("openai-codex", modelId) ??
        ctx.modelRegistry.find("openai", modelId);
      if (upstream && hasNonzeroPricing(upstream.cost)) return upstream;
    }
  }
  return undefined;
}

export function calculateSessionCost(ctx: ExtensionContext): number {
  let cost = 0;
  let activeProvider = ctx.model?.provider;
  let activeModelId = ctx.model?.id;

  for (const entry of ctx.sessionManager.getEntries()) {
    if (entry.type === "model_change") {
      activeProvider = entry.provider;
      activeModelId = entry.modelId;
      continue;
    }

    if (entry.type === "message" && entry.message.role === "assistant") {
      const provider = entry.message.provider ?? activeProvider;
      const selectedModelId = entry.message.model ?? activeModelId;
      cost += calculateUsageCost(
        entry.message.usage,
        pricedModel(ctx, provider, [entry.message.responseModel, selectedModelId, activeModelId]),
      );
      activeProvider = provider;
      activeModelId = selectedModelId;
      continue;
    }

    if (entry.type === "message" && entry.message.role === "toolResult") {
      cost += calculateUsageCost(
        entry.message.usage,
        pricedModel(ctx, activeProvider, [activeModelId]),
      );
      continue;
    }

    if (entry.type === "compaction" || entry.type === "branch_summary") {
      cost += calculateUsageCost(entry.usage, pricedModel(ctx, activeProvider, [activeModelId]));
    }
  }

  return cost;
}
