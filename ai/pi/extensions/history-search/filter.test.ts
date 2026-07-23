import assert from "node:assert/strict";
import test from "node:test";

import { filterHistoryItems, type HistoryItem } from "./filter.ts";

function item(cwd: string, sessionId: string, text: string): HistoryItem {
  return { cwd, sessionId, sessionPath: `/sessions/${sessionId}`, text, timestamp: 1 };
}

test("project scope compares normalized full paths rather than basenames", () => {
  const history = [
    item("/work/personal/app", "one", "personal prompt"),
    item("/work/client/app", "two", "client prompt"),
  ];

  assert.deepEqual(
    filterHistoryItems(history, {
      currentSessionId: "one",
      projectCwd: "/work/personal/app/.",
      query: "",
      scope: "project",
    }).map((entry) => entry.text),
    ["personal prompt"],
  );
});

test("session scope, query matching, and duplicate removal compose", () => {
  const history = [
    item("/work/app", "one", "Run   the tests"),
    item("/work/app", "one", "Run   the tests"),
    item("/work/app", "two", "Run the tests elsewhere"),
  ];

  assert.deepEqual(
    filterHistoryItems(history, {
      currentSessionId: "one",
      projectCwd: "/work/app",
      query: "run the",
      scope: "session",
    }).map((entry) => entry.text),
    ["Run   the tests"],
  );
});
