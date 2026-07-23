import assert from "node:assert/strict";
import test from "node:test";

import { parseRemainingQuotas } from "./quota.ts";

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

test("parses legacy data limits by unit", () => {
  assert.deepEqual(
    parseRemainingQuotas({
      data: {
        limits: [
          { percentage: "10", unit: "3" },
          { remaining_percent: "45", unit: 6 },
        ],
      },
    }),
    { fiveHour: 90, weekly: 45 },
  );
});

test("ignores malformed payloads and values", () => {
  assert.deepEqual(parseRemainingQuotas(null), {});
  assert.deepEqual(parseRemainingQuotas({ rate_limit: { five_hour_limit: { used_percent: "nope" } } }), {});
  assert.deepEqual(parseRemainingQuotas({ data: { limits: "not-an-array" } }), {});
});
