import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

import {
  discoverNestedContextFiles,
  formatNestedContext,
  readStoredContextFile,
  resolveReadTarget,
  updateNestedContextFiles,
} from "./discovery.ts";

function fixture(): { root: string; cleanup: () => void } {
  const created = mkdtempSync(join(tmpdir(), "pi-nested-context-"));
  const root = realpathSync(created);
  return { root, cleanup: () => rmSync(created, { force: true, recursive: true }) };
}

test("discovers every supported filename from broadest to most specific", () => {
  const { root, cleanup } = fixture();
  try {
    const directories = ["package", "package/app", "package/app/src", "package/app/src/deep"];
    for (const directory of directories) mkdirSync(join(root, directory), { recursive: true });

    writeFileSync(join(root, "package", "AGENTS.md"), "agents lower");
    writeFileSync(join(root, "package", "CLAUDE.md"), "claude lower");
    writeFileSync(join(root, "package", "app", "AGENTS.MD"), "agents upper");
    writeFileSync(join(root, "package", "app", "src", "CLAUDE.MD"), "claude upper");
    const target = join(root, "package", "app", "src", "deep", "file.ts");
    writeFileSync(target, "export {};");

    const { files } = discoverNestedContextFiles(root, target);

    assert.deepEqual(
      files.map((file) => [file.path, file.content]),
      [
        [join(root, "package", "AGENTS.md"), "agents lower"],
        [join(root, "package", "CLAUDE.md"), "claude lower"],
        [join(root, "package", "app", "AGENTS.MD"), "agents upper"],
        [join(root, "package", "app", "src", "CLAUDE.MD"), "claude upper"],
      ],
    );
  } finally {
    cleanup();
  }
});

test("does not rediscover files in the cwd or outside it", () => {
  const { root, cleanup } = fixture();
  const outside = fixture();
  try {
    writeFileSync(join(root, "AGENTS.md"), "root instructions");
    writeFileSync(join(root, "file.ts"), "root file");
    writeFileSync(join(outside.root, "CLAUDE.md"), "outside instructions");
    writeFileSync(join(outside.root, "file.ts"), "outside file");

    assert.deepEqual(discoverNestedContextFiles(root, join(root, "file.ts")).files, []);
    assert.deepEqual(discoverNestedContextFiles(root, join(outside.root, "file.ts")).files, []);
  } finally {
    cleanup();
    outside.cleanup();
  }
});

test("resolves read paths the same way for relative, absolute, and @ paths", () => {
  const cwd = resolve("/tmp/project");
  const expected = join(cwd, "src", "file.ts");

  assert.equal(resolveReadTarget(cwd, "src/file.ts"), expected);
  assert.equal(resolveReadTarget(cwd, "@src/file.ts"), expected);
  assert.equal(resolveReadTarget(cwd, expected), expected);
  assert.equal(resolveReadTarget(cwd, pathToFileURL(expected).href), expected);
});

test("restores only supported nested context files", () => {
  const { root, cleanup } = fixture();
  try {
    mkdirSync(join(root, "nested"));
    const contextPath = join(root, "nested", "AGENTS.md");
    const ordinaryPath = join(root, "nested", "README.md");
    writeFileSync(contextPath, "instructions");
    writeFileSync(ordinaryPath, "readme");

    assert.deepEqual(readStoredContextFile(root, contextPath), {
      content: "instructions",
      path: contextPath,
    });
    assert.equal(readStoredContextFile(root, ordinaryPath), undefined);
  } finally {
    cleanup();
  }
});

test("does not follow a nested directory symlink outside the cwd", () => {
  const { root, cleanup } = fixture();
  const outside = fixture();
  try {
    mkdirSync(join(outside.root, "src"));
    writeFileSync(join(outside.root, "AGENTS.md"), "outside instructions");
    writeFileSync(join(outside.root, "src", "file.ts"), "outside file");
    symlinkSync(outside.root, join(root, "linked"));

    const discovery = discoverNestedContextFiles(root, join(root, "linked", "src", "file.ts"));
    assert.deepEqual(discovery, { directories: [], files: [] });
  } finally {
    cleanup();
    outside.cleanup();
  }
});

test("does not reload the cwd context through a nested file symlink", () => {
  const { root, cleanup } = fixture();
  try {
    mkdirSync(join(root, "nested"));
    writeFileSync(join(root, "AGENTS.md"), "root instructions");
    writeFileSync(join(root, "nested", "file.ts"), "nested file");
    symlinkSync(join(root, "AGENTS.md"), join(root, "nested", "AGENTS.md"));

    assert.deepEqual(discoverNestedContextFiles(root, join(root, "nested", "file.ts")).files, []);
  } finally {
    cleanup();
  }
});

test("does not reload a symlink target already loaded through the cwd context", () => {
  const { root, cleanup } = fixture();
  try {
    mkdirSync(join(root, "shared"));
    mkdirSync(join(root, "package"));
    const sharedRules = join(root, "shared", "rules.md");
    writeFileSync(sharedRules, "shared instructions");
    writeFileSync(join(root, "package", "file.ts"), "package file");
    symlinkSync(sharedRules, join(root, "AGENTS.md"));
    symlinkSync(sharedRules, join(root, "package", "AGENTS.md"));

    assert.deepEqual(discoverNestedContextFiles(root, join(root, "package", "file.ts")).files, []);
  } finally {
    cleanup();
  }
});

test("removes stale files and keeps broad instructions before specific ones", () => {
  const { root, cleanup } = fixture();
  try {
    mkdirSync(join(root, "package", "app"), { recursive: true });
    const target = join(root, "package", "app", "file.ts");
    const broadPath = join(root, "package", "CLAUDE.md");
    const specificPath = join(root, "package", "app", "AGENTS.md");
    writeFileSync(target, "file");
    writeFileSync(specificPath, "specific");

    const first = updateNestedContextFiles(root, [], discoverNestedContextFiles(root, target));
    assert.deepEqual(first.files.map((file) => file.path), [specificPath]);

    writeFileSync(broadPath, "broad");
    const second = updateNestedContextFiles(root, first.files, discoverNestedContextFiles(root, target));
    assert.deepEqual(second.files.map((file) => file.path), [broadPath, specificPath]);

    rmSync(specificPath);
    const third = updateNestedContextFiles(root, second.files, discoverNestedContextFiles(root, target));
    assert.deepEqual(third.files.map((file) => file.path), [broadPath]);
  } finally {
    cleanup();
  }
});

test("formats discovered files as scoped project instructions", () => {
  const formatted = formatNestedContext([
    { content: "Use pnpm.", path: "/repo/package/AGENTS.md" },
    { content: "Run tests.", path: "/repo/package/app/CLAUDE.md" },
  ]);

  assert.equal(
    formatted,
    `<project_context>

Project-specific instructions discovered in nested directories are below. Each file applies only to its containing directory and descendants.

<project_instructions path="/repo/package/AGENTS.md">
Use pnpm.
</project_instructions>

<project_instructions path="/repo/package/app/CLAUDE.md">
Run tests.
</project_instructions>

</project_context>`,
  );
});
