import assert from "node:assert/strict";
import test from "node:test";

import { formatTimeUntilReset, parseRemainingQuotas } from "./quota.ts";

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

test("formats compact reset countdowns", () => {
  const now = 1_700_000_000_000;

  assert.equal(formatTimeUntilReset(now + 3 * 24 * 60 * 60_000 + 4 * 60 * 60_000, now), "3d 4h");
  assert.equal(formatTimeUntilReset(now + 2 * 60 * 60_000 + 8 * 60_000, now), "2h 8m");
  assert.equal(formatTimeUntilReset(now + 42 * 60_000, now), "42m");
  assert.equal(formatTimeUntilReset(now + 30_000, now), "<1m");
  assert.equal(formatTimeUntilReset(now - 1, now), undefined);
  assert.equal(formatTimeUntilReset(undefined, now), undefined);
});

test("ignores malformed payloads and values", () => {
  assert.deepEqual(parseRemainingQuotas(null), {});
  assert.deepEqual(parseRemainingQuotas({ rate_limit: { five_hour_limit: { used_percent: "nope" } } }), {});
  assert.deepEqual(parseRemainingQuotas({ data: { limits: "not-an-array" } }), {});
});
