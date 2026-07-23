import { existsSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export const CONTEXT_FILE_NAMES = ["AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"] as const;

const NARROW_NO_BREAK_SPACE = "\u202F";
const UNICODE_SPACES = /[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g;

export type NestedContextFile = {
  content: string;
  path: string;
};

export type NestedContextDiscovery = {
  directories: string[];
  files: NestedContextFile[];
};

function isInside(root: string, target: string): boolean {
  const relativePath = relative(root, target);
  return (
    relativePath !== "" &&
    relativePath !== ".." &&
    !relativePath.startsWith(`..${sep}`) &&
    !isAbsolute(relativePath)
  );
}

function canonicalPath(path: string): string | undefined {
  try {
    return realpathSync(path);
  } catch {
    return undefined;
  }
}

function normalizeReadPath(inputPath: string): string {
  let normalized = inputPath.replace(UNICODE_SPACES, " ");
  if (normalized.startsWith("@")) normalized = normalized.slice(1);

  if (normalized === "~") return homedir();
  if (normalized.startsWith("~/") || (process.platform === "win32" && normalized.startsWith("~\\"))) {
    return join(homedir(), normalized.slice(2));
  }
  if (/^file:\/\//.test(normalized)) return fileURLToPath(normalized);
  return normalized;
}

export function resolveReadTarget(cwd: string, inputPath: string): string {
  const normalized = normalizeReadPath(inputPath);
  const target = isAbsolute(normalized) ? resolve(normalized) : resolve(cwd, normalized);
  if (existsSync(target)) return target;

  const variants = [
    target.replace(/ (AM|PM)\./gi, `${NARROW_NO_BREAK_SPACE}$1.`),
    target.normalize("NFD"),
    target.replace(/'/g, "\u2019"),
    target.normalize("NFD").replace(/'/g, "\u2019"),
  ];
  return variants.find((variant) => variant !== target && existsSync(variant)) ?? target;
}

function nestedDirectories(cwd: string, targetPath: string): { directories: string[]; root?: string } {
  const root = canonicalPath(resolve(cwd));
  const target = canonicalPath(resolve(targetPath));
  if (!root || !target) return { directories: [] };

  const targetDirectory = dirname(target);
  if (!isInside(root, targetDirectory)) return { directories: [], root };

  const directories: string[] = [];
  let current = root;
  for (const segment of relative(root, targetDirectory).split(sep)) {
    if (!segment) continue;
    current = join(current, segment);
    directories.push(current);
  }
  return { directories, root };
}

function loadedAncestorContextTargets(cwd: string): Set<string> {
  const targets = new Set<string>();
  let directory = resolve(cwd);

  while (true) {
    for (const name of CONTEXT_FILE_NAMES) {
      const candidate = join(directory, name);
      if (!existsSync(candidate)) continue;

      try {
        readFileSync(candidate, "utf8");
        const canonical = canonicalPath(candidate);
        if (canonical) targets.add(canonical);
        break;
      } catch {
        // Pi continues to the next candidate when a context file is unreadable.
      }
    }

    const parent = dirname(directory);
    if (parent === directory) break;
    directory = parent;
  }

  return targets;
}

function contextFilesInDirectory(
  root: string,
  directory: string,
  excludedTargets: Set<string>,
): NestedContextFile[] {
  let names: Set<string>;
  try {
    names = new Set(readdirSync(directory));
  } catch {
    return [];
  }

  const files: NestedContextFile[] = [];
  for (const name of CONTEXT_FILE_NAMES) {
    if (!names.has(name)) continue;

    const path = join(directory, name);
    const canonical = canonicalPath(path);
    if (!canonical || excludedTargets.has(canonical) || !isInside(root, dirname(canonical))) continue;

    try {
      files.push({ content: readFileSync(path, "utf8"), path });
    } catch {
      // Ignore unreadable files, matching Pi's context-file discovery behavior.
    }
  }
  return files;
}

export function discoverNestedContextFiles(cwd: string, targetPath: string): NestedContextDiscovery {
  const { directories, root } = nestedDirectories(cwd, targetPath);
  const excludedTargets = loadedAncestorContextTargets(cwd);
  return {
    directories,
    files: root
      ? directories.flatMap((directory) => contextFilesInDirectory(root, directory, excludedTargets))
      : [],
  };
}

export function readStoredContextFile(cwd: string, filePath: string): NestedContextFile | undefined {
  const root = canonicalPath(resolve(cwd));
  const path = resolve(filePath);
  if (
    !root ||
    !CONTEXT_FILE_NAMES.includes(basename(path) as (typeof CONTEXT_FILE_NAMES)[number])
  ) {
    return undefined;
  }

  const canonical = canonicalPath(path);
  if (
    !canonical ||
    loadedAncestorContextTargets(cwd).has(canonical) ||
    !isInside(root, dirname(canonical))
  ) {
    return undefined;
  }

  try {
    return { content: readFileSync(path, "utf8"), path };
  } catch {
    return undefined;
  }
}

export function sortNestedContextFiles(cwd: string, files: NestedContextFile[]): NestedContextFile[] {
  const root = canonicalPath(resolve(cwd)) ?? resolve(cwd);
  const nameOrder = new Map<string, number>(CONTEXT_FILE_NAMES.map((name, index) => [name, index]));

  return [...files].sort((left, right) => {
    const leftDirectory = dirname(left.path);
    const rightDirectory = dirname(right.path);
    const leftDepth = relative(root, leftDirectory).split(sep).filter(Boolean).length;
    const rightDepth = relative(root, rightDirectory).split(sep).filter(Boolean).length;

    return (
      leftDepth - rightDepth ||
      leftDirectory.localeCompare(rightDirectory) ||
      (nameOrder.get(basename(left.path)) ?? Number.MAX_SAFE_INTEGER) -
        (nameOrder.get(basename(right.path)) ?? Number.MAX_SAFE_INTEGER)
    );
  });
}

export function updateNestedContextFiles(
  cwd: string,
  activeFiles: NestedContextFile[],
  discovery: NestedContextDiscovery,
): { changed: boolean; files: NestedContextFile[] } {
  const filesByPath = new Map(activeFiles.map((file) => [file.path, file]));
  const discoveredPaths = new Set(discovery.files.map((file) => file.path));
  const scannedDirectories = new Set(discovery.directories);
  let changed = false;

  for (const path of filesByPath.keys()) {
    if (!scannedDirectories.has(dirname(path)) || discoveredPaths.has(path)) continue;
    filesByPath.delete(path);
    changed = true;
  }

  for (const file of discovery.files) {
    const current = filesByPath.get(file.path);
    if (current?.content === file.content) continue;
    filesByPath.set(file.path, file);
    changed = true;
  }

  return {
    changed,
    files: sortNestedContextFiles(cwd, [...filesByPath.values()]),
  };
}

export function formatNestedContext(files: NestedContextFile[]): string {
  const instructions = files
    .map(({ content, path }) => `<project_instructions path="${path}">\n${content}\n</project_instructions>`)
    .join("\n\n");

  return `<project_context>\n\nProject-specific instructions discovered in nested directories are below. Each file applies only to its containing directory and descendants.\n\n${instructions}\n\n</project_context>`;
}
