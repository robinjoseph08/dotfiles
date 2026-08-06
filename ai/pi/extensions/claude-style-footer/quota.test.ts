import assert from "node:assert/strict";
import test from "node:test";

import {
  aggregateRemainingQuotas,
  formatQuotaUsage,
  formatTimeUntilReset,
  loadOpenAiCodexQuotas,
  parseRemainingQuotas,
} from "./quota.ts";

test("parses remaining and used percentages from named windows", () => {
  assert.deepEqual(
    parseRemainingQuotas({
      rate_limit: {
        five_hour_limit: { used_percent: 25 },
        weekly_limit: { percent_left: "60" },
      },
    }),
    { fiveHour: 75, weekly: 60 },
  );
});

test("classifies windows by duration and clamps percentages", () => {
  assert.deepEqual(
    parseRemainingQuotas({
      rate_limits: {
        primary_window: { limit_window_seconds: 18_000, remaining_percent: 110 },
        secondary_window: { limit_window_seconds: 604_800, percentage: 120 },
      },
    }),
    { fiveHour: 100, weekly: 0 },
  );
});

test("parses reset times from named windows", () => {
  const now = 1_700_000_000_000;

  assert.deepEqual(
    parseRemainingQuotas(
      {
        rate_limit: {
          five_hour_limit: { used_percent: 25, reset_after_seconds: 3_600 },
          weekly_limit: { percent_left: 60, reset_at: "2023-11-16T02:00:00.000Z" },
        },
      },
      now,
    ),
    {
      fiveHour: 75,
      fiveHourResetAt: now + 3_600_000,
      weekly: 60,
      weeklyResetAt: Date.parse("2023-11-16T02:00:00.000Z"),
    },
  );
});

test("parses nested named windows and preserves ambiguous duration fallbacks", () => {
  assert.deepEqual(
    parseRemainingQuotas({
      rate_limit: {
        five_hour_limit: {
          primary_window: {
            used_percent: 20,
            reset_time_ms: "1700003600000",
            limit_window_seconds: 18_000,
          },
        },
        weekly_limit: {
          secondary_window: {
            remaining_percent: 55,
            reset_at: 1_700_600_000,
            limit_window_seconds: 86_400,
          },
        },
      },
    }),
    {
      fiveHour: 80,
      fiveHourResetAt: 1_700_003_600_000,
      weekly: 55,
      weeklyResetAt: 1_700_600_000_000,
    },
  );
});

test("preserves reset-only windows and falls back from malformed absolute resets", () => {
  const now = 1_700_000_000_000;

  assert.deepEqual(
    parseRemainingQuotas(
      {
        rate_limit: {
          five_hour_limit: { reset_at: "invalid", reset_after_seconds: 90 },
          weekly_limit: { reset_time_ms: now + 604_800_000 },
        },
      },
      now,
    ),
    {
      fiveHourResetAt: now + 90_000,
      weeklyResetAt: now + 604_800_000,
    },
  );
});

test("parses legacy data limits by unit", () => {
  assert.deepEqual(
    parseRemainingQuotas({
      data: {
        limits: [
          { percentage: "10", unit: "3", nextResetTime: 1_700_000_000 },
          { remaining_percent: "45", unit: 6, nextResetTime: "1700600000000" },
        ],
      },
    }),
    {
      fiveHour: 90,
      fiveHourResetAt: 1_700_000_000_000,
      weekly: 45,
      weeklyResetAt: 1_700_600_000_000,
    },
  );
});

test("shows the most constrained account and its reset per window", () => {
  assert.deepEqual(
    aggregateRemainingQuotas([
      {
        fiveHour: 100,
        fiveHourResetAt: 1_700_018_000_000,
        weekly: 80,
        weeklyResetAt: 1_700_604_800_000,
      },
      {
        fiveHour: 40,
        fiveHourResetAt: 1_700_009_000_000,
        weekly: 20,
        weeklyResetAt: 1_700_302_400_000,
      },
    ]),
    {
      fiveHour: 40,
      fiveHourResetAt: 1_700_009_000_000,
      weekly: 20,
      weeklyResetAt: 1_700_302_400_000,
      accountMinimum: true,
    },
  );
});

test("leaves an account-minimum window unknown when any account omits it", () => {
  assert.deepEqual(
    aggregateRemainingQuotas([
      { fiveHour: 100, fiveHourResetAt: 1_700_018_000_000 },
      { weekly: 40, weeklyResetAt: 1_700_604_800_000 },
    ]),
    { accountMinimum: true },
  );
  assert.deepEqual(aggregateRemainingQuotas([]), {});
});

test("keeps a constrained percentage when its reset is unknown", () => {
  assert.deepEqual(
    aggregateRemainingQuotas([
      { fiveHour: 40 },
      { fiveHour: 80, fiveHourResetAt: 1_700_018_000_000 },
    ]),
    { fiveHour: 40, accountMinimum: true },
  );
});

test("rejects an invalid enabled CPA credential", async () => {
  const { mkdtemp, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const previousFetch = globalThis.fetch;
  const directory = await mkdtemp(join(tmpdir(), "claude-style-footer-"));
  process.env.CLIPROXYAPI_AUTH_DIR = directory;
  await Promise.all([
    writeFile(join(directory, "healthy.json"), JSON.stringify({ type: "codex", access_token: "healthy", account_id: "one" })),
    writeFile(join(directory, "invalid.json"), JSON.stringify({ type: "codex", access_token: "missing-account" })),
  ]);
  globalThis.fetch = async () => new Response("should not fetch", { status: 500 });

  try {
    await assert.rejects(
      loadOpenAiCodexQuotas({ model: { provider: "cpa" } } as never),
      /complete CPA credential set/,
    );
  } finally {
    globalThis.fetch = previousFetch;
    await rm(directory, { recursive: true, force: true });
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("rejects malformed JSON in the CPA credential directory", async () => {
  const { mkdtemp, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const directory = await mkdtemp(join(tmpdir(), "claude-style-footer-"));
  process.env.CLIPROXYAPI_AUTH_DIR = directory;
  await writeFile(join(directory, "malformed.json"), "{not-json");

  try {
    await assert.rejects(
      loadOpenAiCodexQuotas({ model: { provider: "cpa" } } as never),
      /complete CPA credential set/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("rejects an existing CPA credential directory without enabled Codex accounts", async () => {
  const { mkdtemp, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const directory = await mkdtemp(join(tmpdir(), "claude-style-footer-"));
  process.env.CLIPROXYAPI_AUTH_DIR = directory;
  await writeFile(join(directory, "disabled.json"), JSON.stringify({ type: "codex", disabled: true }));

  try {
    await assert.rejects(
      loadOpenAiCodexQuotas({ model: { provider: "cpa" } } as never),
      /complete CPA credential set/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("rejects a configured CPA credential path that is not a directory", async () => {
  const { mkdtemp, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const directory = await mkdtemp(join(tmpdir(), "claude-style-footer-"));
  const file = join(directory, "accounts");
  process.env.CLIPROXYAPI_AUTH_DIR = file;
  await writeFile(file, "not-a-directory");

  try {
    await assert.rejects(
      loadOpenAiCodexQuotas({ model: { provider: "cpa" } } as never),
      /complete CPA credential set/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("rejects an incomplete CPA pool snapshot", async () => {
  const { mkdtemp, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const previousFetch = globalThis.fetch;
  const directory = await mkdtemp(join(tmpdir(), "claude-style-footer-"));
  process.env.CLIPROXYAPI_AUTH_DIR = directory;
  await Promise.all([
    writeFile(join(directory, "healthy.json"), JSON.stringify({ type: "codex", access_token: "healthy", account_id: "one" })),
    writeFile(join(directory, "expired.json"), JSON.stringify({ type: "codex", access_token: "expired", account_id: "two" })),
  ]);

  globalThis.fetch = async (_input, init) => {
    const authorization = new Headers(init?.headers).get("authorization");
    if (authorization === "Bearer expired") return new Response("expired", { status: 401 });
    return new Response(JSON.stringify({ rate_limit: { five_hour_limit: { used_percent: 25 } } }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  try {
    await assert.rejects(
      loadOpenAiCodexQuotas({ model: { provider: "cpa" } } as never),
      /complete CPA quota snapshot/,
    );
  } finally {
    globalThis.fetch = previousFetch;
    await rm(directory, { recursive: true, force: true });
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("falls back to Pi Codex auth when CPA is not configured", async () => {
  const previousAccountsDir = process.env.CLIPROXYAPI_AUTH_DIR;
  const previousFetch = globalThis.fetch;
  process.env.CLIPROXYAPI_AUTH_DIR = `/tmp/claude-style-footer-missing-${process.pid}-${Date.now()}`;

  let requestedAuthorization: string | null = null;
  globalThis.fetch = async (_input, init) => {
    requestedAuthorization = new Headers(init?.headers).get("authorization");
    return new Response(
      JSON.stringify({
        rate_limit: {
          primary_window: {
            used_percent: 25,
            limit_window_seconds: 18_000,
            reset_at: 1_700_018_000,
          },
          secondary_window: {
            used_percent: 40,
            limit_window_seconds: 604_800,
            reset_at: 1_700_604_800,
          },
        },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };

  try {
    const quotas = await loadOpenAiCodexQuotas({
      model: { provider: "cpa" },
      modelRegistry: {
        getAvailable: () => [{ provider: "openai-codex" }],
        getApiKeyAndHeaders: async () => ({
          ok: true,
          apiKey: "pi-codex-token",
          headers: { "chatgpt-account-id": "pi-account" },
        }),
      },
    } as never);

    assert.equal(requestedAuthorization, "Bearer pi-codex-token");
    assert.deepEqual(quotas, {
      fiveHour: 75,
      fiveHourResetAt: 1_700_018_000_000,
      weekly: 60,
      weeklyResetAt: 1_700_604_800_000,
    });
  } finally {
    globalThis.fetch = previousFetch;
    if (previousAccountsDir === undefined) delete process.env.CLIPROXYAPI_AUTH_DIR;
    else process.env.CLIPROXYAPI_AUTH_DIR = previousAccountsDir;
  }
});

test("formats compact reset countdowns", () => {
  const now = 1_700_000_000_000;

  assert.equal(formatTimeUntilReset(now + 3 * 24 * 60 * 60_000 + 4 * 60 * 60_000, now), "3d 4h");
  assert.equal(formatTimeUntilReset(now + 2 * 60 * 60_000 + 8 * 60_000, now), "2h 8m");
  assert.equal(formatTimeUntilReset(now + 42 * 60_000, now), "42m");
  assert.equal(formatTimeUntilReset(now + 30_000, now), "<1m");
  assert.equal(formatTimeUntilReset(now + 59_001, now), "1m");
  assert.equal(formatTimeUntilReset(now + 3_599_001, now), "1h 0m");
  assert.equal(formatTimeUntilReset(now + 86_399_001, now), "1d 0h");
  assert.equal(formatTimeUntilReset(now - 1, now), undefined);
  assert.equal(formatTimeUntilReset(undefined, now), undefined);
  assert.equal(formatTimeUntilReset(Number.POSITIVE_INFINITY, now), undefined);
});

test("formats reset countdowns beside quota usage", () => {
  const now = 1_700_000_000_000;

  assert.equal(formatQuotaUsage("5h", 74.6, now + 2 * 60 * 60_000 + 8 * 60_000, now), "5h:75% (2h 8m)");
  assert.equal(formatQuotaUsage("week", undefined, undefined, now), "week:?");
});

test("ignores malformed payloads and values", () => {
  assert.deepEqual(parseRemainingQuotas(null), {});
  assert.deepEqual(parseRemainingQuotas({ rate_limit: { five_hour_limit: { used_percent: "nope" } } }), {});
  assert.deepEqual(parseRemainingQuotas({ data: { limits: "not-an-array" } }), {});
  assert.deepEqual(
    parseRemainingQuotas({
      rate_limit: {
        primary_window: { reset_after_seconds: Number.MAX_VALUE },
        secondary_window: { remaining_percent: 40, limit_window_seconds: -1 },
      },
    }),
    { weekly: 40 },
  );
});
