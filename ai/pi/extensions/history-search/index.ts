import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { createInterface } from "node:readline";

import { getAgentDir, type ExtensionAPI, type ExtensionContext, type Theme } from "@earendil-works/pi-coding-agent";
import {
  type Component,
  type Focusable,
  Input,
  matchesKey,
  type TUI,
  truncateToWidth,
} from "@earendil-works/pi-tui";

type HistoryScope = "everywhere" | "project" | "session";

type HistoryItem = {
  cwd: string;
  sessionId: string;
  sessionPath: string;
  text: string;
  timestamp: number;
};

type CachedSession = {
  cwd: string;
  items: HistoryItem[];
  mtimeMs: number;
  sessionId: string;
  size: number;
};

type SessionFile = {
  mtimeMs: number;
  path: string;
  size: number;
};

const CACHE = new Map<string, CachedSession>();
const MAX_VISIBLE_RESULTS = 8;
const SCOPES: HistoryScope[] = ["everywhere", "project", "session"];
const SKILL_BLOCK_PATTERN = /<skill name="([^"]+)"[^>]*>[\s\S]*?<\/skill>((?:\r?\n){2})?/g;

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";

  return content
    .filter((part): part is { type: "text"; text: string } => {
      if (!part || typeof part !== "object") return false;
      const candidate = part as { type?: unknown; text?: unknown };
      return candidate.type === "text" && typeof candidate.text === "string";
    })
    .map((part) => part.text)
    .join("\n");
}

function collapseExpandedSkills(text: string): string {
  return text
    .replace(SKILL_BLOCK_PATTERN, (_block, name: string, argumentSeparator: string | undefined) =>
      argumentSeparator ? `/skill:${name} ` : `/skill:${name}`,
    )
    .trim();
}

function historyItemFromEntry(
  entry: unknown,
  cwd: string,
  sessionId: string,
  sessionPath: string,
): HistoryItem | undefined {
  if (!entry || typeof entry !== "object") return undefined;
  const candidate = entry as {
    message?: { content?: unknown; role?: unknown; timestamp?: unknown };
    timestamp?: unknown;
    type?: unknown;
  };
  if (candidate.type !== "message" || candidate.message?.role !== "user") return undefined;

  const text = collapseExpandedSkills(extractText(candidate.message.content));
  if (!text) return undefined;

  const entryTimestamp = typeof candidate.timestamp === "string" ? Date.parse(candidate.timestamp) : Number.NaN;
  const messageTimestamp =
    typeof candidate.message.timestamp === "number" ? candidate.message.timestamp : Number.NaN;

  return {
    cwd,
    sessionId,
    sessionPath,
    text,
    timestamp: Number.isFinite(entryTimestamp)
      ? entryTimestamp
      : Number.isFinite(messageTimestamp)
        ? messageTimestamp
        : 0,
  };
}

async function readSession(file: SessionFile, signal: AbortSignal): Promise<CachedSession | undefined> {
  let cwd = "";
  let sessionId = "";
  const items: HistoryItem[] = [];

  try {
    const lines = createInterface({
      crlfDelay: Infinity,
      input: createReadStream(file.path, { encoding: "utf8", signal }),
    });

    for await (const line of lines) {
      if (signal.aborted) return undefined;
      if (!line.includes('"type":"session"') && !line.includes('"role":"user"')) continue;

      let entry: unknown;
      try {
        entry = JSON.parse(line);
      } catch {
        continue;
      }

      if (entry && typeof entry === "object" && (entry as { type?: unknown }).type === "session") {
        const header = entry as { cwd?: unknown; id?: unknown };
        cwd = typeof header.cwd === "string" ? header.cwd : "";
        sessionId = typeof header.id === "string" ? header.id : "";
        continue;
      }

      const item = historyItemFromEntry(entry, cwd, sessionId, file.path);
      if (item) items.push(item);
    }
  } catch {
    return undefined;
  }

  return {
    cwd,
    items,
    mtimeMs: file.mtimeMs,
    sessionId,
    size: file.size,
  };
}

async function findSessionFiles(root: string, signal: AbortSignal): Promise<SessionFile[]> {
  const files: SessionFile[] = [];

  async function visit(directory: string): Promise<void> {
    if (signal.aborted) return;
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (signal.aborted) return;
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        await visit(path);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith(".jsonl")) continue;

      try {
        const metadata = await stat(path);
        files.push({ mtimeMs: metadata.mtimeMs, path, size: metadata.size });
      } catch {
        // The session may have been deleted while scanning.
      }
    }
  }

  await visit(root);
  return files;
}

async function refreshHistory(ctx: ExtensionContext, signal: AbortSignal): Promise<HistoryItem[]> {
  const roots = new Set([resolve(getAgentDir(), "sessions")]);
  const currentSessionDir = ctx.sessionManager.getSessionDir();
  if (currentSessionDir) roots.add(resolve(currentSessionDir));
  const discovered = new Map<string, SessionFile>();

  for (const root of roots) {
    for (const file of await findSessionFiles(root, signal)) {
      discovered.set(file.path, file);
    }
  }
  if (signal.aborted) return [];

  for (const cachedPath of CACHE.keys()) {
    if (!discovered.has(cachedPath)) CACHE.delete(cachedPath);
  }

  for (const file of discovered.values()) {
    const cached = CACHE.get(file.path);
    if (cached && cached.mtimeMs === file.mtimeMs && cached.size === file.size) continue;

    const parsed = await readSession(file, signal);
    if (signal.aborted) return [];
    if (parsed) CACHE.set(file.path, parsed);
  }

  const currentPath = ctx.sessionManager.getSessionFile();
  const history = [...CACHE.entries()]
    .filter(([path]) => path !== currentPath)
    .flatMap(([, session]) => session.items);

  const currentCwd = ctx.sessionManager.getHeader()?.cwd ?? ctx.cwd;
  const currentSessionId = ctx.sessionManager.getSessionId();
  const currentSessionPath = currentPath ?? `<session:${currentSessionId}>`;
  for (const entry of ctx.sessionManager.getEntries()) {
    const item = historyItemFromEntry(entry, currentCwd, currentSessionId, currentSessionPath);
    if (item) history.push(item);
  }

  return history.sort((left, right) => right.timestamp - left.timestamp);
}

function normalizedProjectPath(path: string): string {
  return resolve(path || ".");
}

function formatProject(cwd: string): string {
  return cwd ? basename(cwd) || cwd : "unknown";
}

function formatTimestamp(timestamp: number): string {
  if (!timestamp) return "unknown time";
  const date = new Date(timestamp);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) {
    return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  }
  return date.toLocaleDateString([], { day: "numeric", month: "short" });
}

class HistorySearchComponent implements Component, Focusable {
  private readonly input = new Input();
  private scopeIndex = 0;
  private selectedIndex = 0;
  private _focused = false;

  constructor(
    private readonly tui: TUI,
    private readonly theme: Theme,
    private readonly history: HistoryItem[],
    private readonly projectCwd: string,
    private readonly currentSessionId: string,
    initialQuery: string,
    private readonly done: (value: string | undefined) => void,
  ) {
    this.input.setValue(initialQuery);
    this.input.onEscape = () => this.done(undefined);
    this.input.onSubmit = () => this.acceptSelection();
  }

  get focused(): boolean {
    return this._focused;
  }

  set focused(value: boolean) {
    this._focused = value;
    this.input.focused = value;
  }

  private get scope(): HistoryScope {
    return SCOPES[this.scopeIndex] ?? "everywhere";
  }

  private filteredHistory(): HistoryItem[] {
    const currentProject = normalizedProjectPath(this.projectCwd);
    const query = this.input.getValue().trim().toLocaleLowerCase();
    const seen = new Set<string>();

    return this.history.filter((item) => {
      if (this.scope === "project" && normalizedProjectPath(item.cwd) !== currentProject) return false;
      if (this.scope === "session" && item.sessionId !== this.currentSessionId) return false;
      if (query && !item.text.replace(/\s+/g, " ").toLocaleLowerCase().includes(query)) return false;
      if (seen.has(item.text)) return false;
      seen.add(item.text);
      return true;
    });
  }

  private moveSelection(offset: number): void {
    const results = this.filteredHistory();
    if (results.length === 0) {
      this.selectedIndex = 0;
      return;
    }
    this.selectedIndex = Math.max(0, Math.min(results.length - 1, this.selectedIndex + offset));
  }

  private cycleScope(): void {
    this.scopeIndex = (this.scopeIndex + 1) % SCOPES.length;
    this.selectedIndex = 0;
  }

  private acceptSelection(): void {
    const selected = this.filteredHistory()[this.selectedIndex];
    if (selected) this.done(selected.text);
  }

  handleInput(data: string): void {
    if (matchesKey(data, "ctrl+s")) {
      this.cycleScope();
    } else if (matchesKey(data, "ctrl+r") || matchesKey(data, "down")) {
      this.moveSelection(1);
    } else if (matchesKey(data, "up")) {
      this.moveSelection(-1);
    } else if (matchesKey(data, "enter")) {
      this.acceptSelection();
      return;
    } else if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
      this.done(undefined);
      return;
    } else {
      const previousQuery = this.input.getValue();
      this.input.handleInput(data);
      if (this.input.getValue() !== previousQuery) this.selectedIndex = 0;
    }

    this.invalidate();
    this.tui.requestRender();
  }

  invalidate(): void {
    this.input.invalidate();
  }

  render(width: number): string[] {
    if (width <= 0) return [];
    const inputWidth = Math.max(1, width - 1);
    const results = this.filteredHistory();
    this.selectedIndex = Math.min(this.selectedIndex, Math.max(0, results.length - 1));

    const title = `History search [${this.scope}]`;
    const lines = [
      this.theme.fg("accent", this.theme.bold(truncateToWidth(title, width))),
      ...this.input.render(inputWidth).map((line) => truncateToWidth(` ${line}`, width)),
      "",
    ];

    if (results.length === 0) {
      lines.push(this.theme.fg("muted", truncateToWidth("  No matching prompts", width)));
    } else {
      const firstVisibleIndex = Math.max(
        0,
        Math.min(this.selectedIndex, results.length - MAX_VISIBLE_RESULTS),
      );
      for (const [visibleIndex, item] of results
        .slice(firstVisibleIndex, firstVisibleIndex + MAX_VISIBLE_RESULTS)
        .entries()) {
        const resultIndex = firstVisibleIndex + visibleIndex;
        const prefix = resultIndex === this.selectedIndex ? "› " : "  ";
        const metadata = `[${formatProject(item.cwd)} · ${formatTimestamp(item.timestamp)}] `;
        const preview = item.text.replace(/\s+/g, " ");
        const line = truncateToWidth(`${prefix}${metadata}${preview}`, width);
        lines.push(resultIndex === this.selectedIndex ? this.theme.fg("accent", line) : line);
      }
    }

    lines.push("");
    lines.push(
      this.theme.fg(
        "dim",
        truncateToWidth("Ctrl+R/↓ older · ↑ newer · Ctrl+S scope · Enter use · Esc cancel", width),
      ),
    );
    return lines;
  }
}

export default function historySearch(pi: ExtensionAPI): void {
  let opening = false;
  let preload: Promise<HistoryItem[]> | undefined;
  let sessionController: AbortController | undefined;

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    sessionController?.abort();
    sessionController = new AbortController();
    preload = refreshHistory(ctx, sessionController.signal).catch(() => []);
  });

  pi.on("session_shutdown", () => {
    sessionController?.abort();
    sessionController = undefined;
    preload = undefined;
  });

  pi.registerShortcut("ctrl+r", {
    description: "Search prompt history",
    handler: async (ctx) => {
      if (ctx.mode !== "tui" || opening) return;
      opening = true;
      ctx.ui.setStatus("history-search", "loading history...");

      try {
        const controller = sessionController;
        if (!controller) return;
        await preload;
        if (controller !== sessionController || controller.signal.aborted) return;
        preload = undefined;
        const history = await refreshHistory(ctx, controller.signal);
        if (controller !== sessionController || controller.signal.aborted) return;
        ctx.ui.setStatus("history-search", undefined);
        const initialQuery = ctx.ui.getEditorText();
        const selected = await ctx.ui.custom<string | undefined>((tui, theme, _keybindings, done) =>
          new HistorySearchComponent(
            tui,
            theme,
            history,
            ctx.cwd,
            ctx.sessionManager.getSessionId(),
            initialQuery,
            done,
          ),
        );
        if (selected !== undefined) ctx.ui.setEditorText(selected);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`history-search: ${message}`, "error");
      } finally {
        ctx.ui.setStatus("history-search", undefined);
        opening = false;
      }
    },
  });
}
