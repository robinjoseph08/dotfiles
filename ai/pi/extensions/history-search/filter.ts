import { resolve } from "node:path";

export type HistoryScope = "everywhere" | "project" | "session";

export type HistoryItem = {
  cwd: string;
  sessionId: string;
  sessionPath: string;
  text: string;
  timestamp: number;
};

type FilterOptions = {
  currentSessionId: string;
  projectCwd: string;
  query: string;
  scope: HistoryScope;
};

function normalizedProjectPath(path: string): string {
  return resolve(path || ".");
}

export function filterHistoryItems(history: HistoryItem[], options: FilterOptions): HistoryItem[] {
  const currentProject = normalizedProjectPath(options.projectCwd);
  const query = options.query.trim().toLocaleLowerCase();
  const seen = new Set<string>();

  return history.filter((item) => {
    if (options.scope === "project" && normalizedProjectPath(item.cwd) !== currentProject) return false;
    if (options.scope === "session" && item.sessionId !== options.currentSessionId) return false;
    if (query && !item.text.replace(/\s+/g, " ").toLocaleLowerCase().includes(query)) return false;
    if (seen.has(item.text)) return false;
    seen.add(item.text);
    return true;
  });
}
