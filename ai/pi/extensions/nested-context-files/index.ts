import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import {
  discoverNestedContextFiles,
  formatNestedContext,
  readStoredContextFile,
  resolveReadTarget,
  sortNestedContextFiles,
  updateNestedContextFiles,
  type NestedContextFile,
} from "./discovery.ts";

const MESSAGE_TYPE = "nested-context-files";
const STATE_TYPE = "nested-context-files:state";

type StoredState = {
  paths: string[];
};

function storedPaths(data: unknown): string[] | undefined {
  if (!data || typeof data !== "object") return undefined;
  const paths = (data as { paths?: unknown }).paths;
  if (!Array.isArray(paths) || !paths.every((path) => typeof path === "string")) return undefined;
  return paths;
}

function restoreContextFiles(ctx: ExtensionContext): Map<string, NestedContextFile> {
  let paths: string[] = [];

  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "custom" || entry.customType !== STATE_TYPE) continue;
    paths = storedPaths(entry.data) ?? paths;
  }

  const files = new Map<string, NestedContextFile>();
  for (const path of paths) {
    const file = readStoredContextFile(ctx.cwd, path);
    if (file) files.set(file.path, file);
  }
  return new Map(sortNestedContextFiles(ctx.cwd, [...files.values()]).map((file) => [file.path, file]));
}

export default function nestedContextFiles(pi: ExtensionAPI): void {
  let activeFiles = new Map<string, NestedContextFile>();

  const restore = (ctx: ExtensionContext): void => {
    activeFiles = restoreContextFiles(ctx);
  };

  pi.on("session_start", (_event, ctx) => restore(ctx));
  pi.on("session_tree", (_event, ctx) => restore(ctx));

  pi.on("tool_result", (event, ctx) => {
    if (event.toolName !== "read" || event.isError) return;

    const inputPath = event.input.path;
    if (typeof inputPath !== "string") return;

    const targetPath = resolveReadTarget(ctx.cwd, inputPath);
    const discovery = discoverNestedContextFiles(ctx.cwd, targetPath);
    const update = updateNestedContextFiles(ctx.cwd, [...activeFiles.values()], discovery);
    if (!update.changed) return;

    activeFiles = new Map(update.files.map((file) => [file.path, file]));
    const state: StoredState = { paths: [...activeFiles.keys()] };
    pi.appendEntry(STATE_TYPE, state);
  });

  pi.on("context", (event) => {
    if (activeFiles.size === 0) return;

    const message: (typeof event.messages)[number] = {
      role: "custom",
      customType: MESSAGE_TYPE,
      content: formatNestedContext([...activeFiles.values()]),
      display: false,
      details: { paths: [...activeFiles.keys()] },
      timestamp: Date.now(),
    };

    return { messages: [...event.messages, message] };
  });
}
