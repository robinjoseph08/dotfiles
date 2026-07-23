import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import nestedContextFiles from "./index.ts";

type CustomEntry = {
  customType: string;
  data: unknown;
  type: "custom";
};

type Handler = (event: any, ctx: any) => any;

function fixture(): { root: string; cleanup: () => void } {
  const created = mkdtempSync(join(tmpdir(), "pi-nested-context-extension-"));
  const root = realpathSync(created);
  mkdirSync(join(root, "package", "src"), { recursive: true });
  writeFileSync(join(root, "package", "src", "file.ts"), "export {};");
  return { root, cleanup: () => rmSync(created, { force: true, recursive: true }) };
}

function harness(cwd: string, initialBranch: CustomEntry[] = []) {
  const handlers = new Map<string, Handler[]>();
  const entries = [...initialBranch];
  let branch = entries;

  nestedContextFiles({
    appendEntry(customType: string, data: unknown) {
      const entry: CustomEntry = { customType, data, type: "custom" };
      entries.push(entry);
      if (branch === entries) branch = entries;
    },
    on(name: string, handler: Handler) {
      handlers.set(name, [...(handlers.get(name) ?? []), handler]);
    },
  } as never);

  const ctx = {
    cwd,
    sessionManager: {
      getBranch: () => branch,
    },
  };

  return {
    entries,
    async fire(name: string, event: unknown) {
      let result;
      for (const handler of handlers.get(name) ?? []) result = await handler(event, ctx);
      return result;
    },
    setBranch(next: CustomEntry[]) {
      branch = next;
    },
  };
}

function readResult(path: string, isError = false) {
  return {
    content: [{ text: "file", type: "text" }],
    details: undefined,
    input: { path },
    isError,
    toolCallId: "read-1",
    toolName: "read",
    type: "tool_result",
  };
}

test("loads nested instructions only after a successful read", async () => {
  const { root, cleanup } = fixture();
  try {
    writeFileSync(join(root, "package", "AGENTS.md"), "USE_NESTED_RULE");
    const app = harness(root);
    await app.fire("session_start", { reason: "startup", type: "session_start" });

    assert.equal(await app.fire("context", { messages: [], type: "context" }), undefined);
    await app.fire("tool_result", readResult("package/src/file.ts", true));
    assert.equal(app.entries.length, 0);

    await app.fire("tool_result", readResult("package/src/file.ts"));
    assert.equal(app.entries.length, 1);

    const result = (await app.fire("context", { messages: [], type: "context" })) as {
      messages: Array<{ content: string }>;
    };
    assert.equal(result.messages.length, 1);
    assert.match(result.messages[0]?.content ?? "", /USE_NESTED_RULE/);
  } finally {
    cleanup();
  }
});

test("restores current contents and follows tree navigation state", async () => {
  const { root, cleanup } = fixture();
  try {
    const contextPath = join(root, "package", "CLAUDE.md");
    writeFileSync(contextPath, "original instructions");

    const first = harness(root);
    await first.fire("session_start", { reason: "startup", type: "session_start" });
    await first.fire("tool_result", readResult("package/src/file.ts"));
    const savedState = [...first.entries];

    writeFileSync(contextPath, "updated instructions");
    const resumed = harness(root, savedState);
    await resumed.fire("session_start", { reason: "resume", type: "session_start" });
    const restored = (await resumed.fire("context", { messages: [], type: "context" })) as {
      messages: Array<{ content: string }>;
    };
    assert.match(restored.messages[0]?.content ?? "", /updated instructions/);

    resumed.setBranch([]);
    await resumed.fire("session_tree", { newLeafId: null, oldLeafId: "old", type: "session_tree" });
    assert.equal(await resumed.fire("context", { messages: [], type: "context" }), undefined);
  } finally {
    cleanup();
  }
});

test("removes deleted instructions after another successful read in their scope", async () => {
  const { root, cleanup } = fixture();
  try {
    const contextPath = join(root, "package", "AGENTS.md");
    writeFileSync(contextPath, "temporary instructions");

    const app = harness(root);
    await app.fire("session_start", { reason: "startup", type: "session_start" });
    await app.fire("tool_result", readResult("package/src/file.ts"));
    rmSync(contextPath);
    await app.fire("tool_result", readResult("package/src/file.ts"));

    assert.equal(app.entries.length, 2);
    assert.equal(await app.fire("context", { messages: [], type: "context" }), undefined);
    assert.deepEqual(app.entries[1]?.data, { paths: [] });
  } finally {
    cleanup();
  }
});
