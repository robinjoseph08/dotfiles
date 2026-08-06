import assert from "node:assert/strict";
import test from "node:test";

import type { Api, Model } from "@earendil-works/pi-ai";

import {
  calculateSessionCost,
  calculateUsageCost,
  formatSessionCost,
  hasNonzeroPricing,
} from "./cost.ts";

const modelCost = {
  input: 5,
  output: 30,
  cacheRead: 0.5,
  cacheWrite: 6.25,
  tiers: [
    {
      inputTokensAbove: 272_000,
      input: 10,
      output: 45,
      cacheRead: 1,
      cacheWrite: 12.5,
    },
  ],
};

const cpaModel: Model<Api> = {
  id: "gpt-5.6-sol",
  name: "GPT-5.6 Sol",
  api: "openai-codex-responses",
  provider: "cpa",
  baseUrl: "http://localhost",
  reasoning: true,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 272_000,
  maxTokens: 128_000,
};

const upstreamModel: Model<Api> = { ...cpaModel, provider: "openai-codex", cost: modelCost };

function usage(overrides: Record<string, unknown> = {}) {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    ...overrides,
  };
}

function context(entries: unknown[]) {
  return {
    model: cpaModel,
    modelRegistry: {
      find(provider: string, modelId: string) {
        if (modelId !== "gpt-5.6-sol") return undefined;
        if (provider === "cpa") return cpaModel;
        if (provider === "openai-codex") return upstreamModel;
        return undefined;
      },
    },
    sessionManager: { getEntries: () => entries },
  } as never;
}

test("uses a reported nonzero cost", () => {
  assert.equal(calculateUsageCost(usage({ input: 1_000, cost: { total: 0.123 } }), upstreamModel), 0.123);
});

test("calculates cost when CPA reports zero", () => {
  assert.equal(
    calculateUsageCost(
      usage({ input: 10_000, output: 1_000, cacheRead: 20_000 }),
      upstreamModel,
    ),
    0.09,
  );
});

test("applies the highest matching request-wide pricing tier", () => {
  assert.equal(
    calculateUsageCost(
      usage({ input: 100_000, output: 10_000, cacheRead: 200_000 }),
      upstreamModel,
    ),
    1.65,
  );
});

test("prices CPA assistant, tool, and summary usage with the active model", () => {
  assert.equal(
    calculateSessionCost(
      context([
        { type: "model_change", provider: "cpa", modelId: "gpt-5.6-sol" },
        {
          type: "message",
          message: {
            role: "assistant",
            provider: "cpa",
            model: "gpt-5.6-sol",
            usage: usage({ input: 10_000 }),
          },
        },
        {
          type: "message",
          message: { role: "toolResult", usage: usage({ output: 1_000 }) },
        },
        { type: "compaction", usage: usage({ cacheRead: 20_000 }) },
        { type: "branch_summary", usage: usage({ input: 1_000 }) },
      ]),
    ),
    0.095,
  );
});

test("follows model changes while calculating session cost", () => {
  const otherModel: Model<Api> = {
    ...upstreamModel,
    id: "other",
    cost: { ...modelCost, input: 10 },
  };
  const ctx = context([
    { type: "model_change", provider: "cpa", modelId: "gpt-5.6-sol" },
    { type: "compaction", usage: usage({ input: 1_000 }) },
    { type: "model_change", provider: "cpa", modelId: "other" },
    { type: "branch_summary", usage: usage({ input: 1_000 }) },
  ]) as {
    modelRegistry: { find(provider: string, modelId: string): unknown };
  };
  const originalFind = ctx.modelRegistry.find.bind(ctx.modelRegistry);
  ctx.modelRegistry.find = (provider, modelId) =>
    modelId === "other" && provider === "openai-codex" ? otherModel : originalFind(provider, modelId);

  assert.equal(calculateSessionCost(ctx as never), 0.015);
});

test("formats small positive costs without displaying zero", () => {
  assert.equal(formatSessionCost(0), "$0.000");
  assert.equal(formatSessionCost(0.0004), "$0.000400");
  assert.equal(formatSessionCost(0.0000004), "$4.00e-7");
  assert.equal(formatSessionCost(0.040825), "$0.041");
});

test("returns zero when no pricing is known", () => {
  assert.equal(calculateUsageCost(usage({ input: 10_000, output: 1_000 }), cpaModel), 0);
  assert.equal(hasNonzeroPricing({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }), false);
  assert.equal(hasNonzeroPricing(modelCost), true);
});
