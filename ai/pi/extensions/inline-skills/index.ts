import { readFileSync } from "node:fs";
import { dirname } from "node:path";

import { stripFrontmatter, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fuzzyFilter, type AutocompleteItem } from "@earendil-works/pi-tui";

import { transformInlineSkills } from "./transform.ts";

const MAX_SUGGESTIONS = 20;
const SKILL_COMMAND_PREFIX = "skill:";

type InlineSkill = {
  commandName: string;
  description?: string;
  filePath: string;
  name: string;
  baseDir: string;
};

function getSkills(pi: ExtensionAPI): InlineSkill[] {
  return pi
    .getCommands()
    .filter((command) => command.source === "skill" && command.name.startsWith(SKILL_COMMAND_PREFIX))
    .map((command) => ({
      commandName: command.name,
      ...(command.description ? { description: command.description } : {}),
      filePath: command.sourceInfo.path,
      name: command.name.slice(SKILL_COMMAND_PREFIX.length),
      baseDir: dirname(command.sourceInfo.path),
    }));
}

function extractInlineSlashPrefix(textBeforeCursor: string): { prefix: string; query: string } | undefined {
  const match = textBeforeCursor.match(/(?:^|[ \t])(\/([a-zA-Z0-9:_-]*))$/);
  if (!match?.[1]) return undefined;

  const prefix = match[1];
  const tokenStart = textBeforeCursor.length - prefix.length;
  if (tokenStart === 0) return undefined;

  return { prefix, query: match[2] ?? "" };
}

function skillItems(skills: InlineSkill[], query: string): AutocompleteItem[] {
  return fuzzyFilter(skills, query, (skill) => `${skill.commandName} ${skill.description ?? ""}`)
    .slice(0, MAX_SUGGESTIONS)
    .map((skill) => ({
      value: `/${skill.commandName}`,
      label: skill.commandName,
      ...(skill.description ? { description: skill.description } : {}),
    }));
}

function formatSkillBlock(skill: InlineSkill): string {
  const content = readFileSync(skill.filePath, "utf8");
  const body = stripFrontmatter(content).trim();
  return `<skill name="${skill.name}" location="${skill.filePath}">\nReferences are relative to ${skill.baseDir}.\n\n${body}\n</skill>`;
}

export default function inlineSkills(pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    ctx.ui.addAutocompleteProvider((current) => ({
      async getSuggestions(lines, cursorLine, cursorCol, options) {
        const currentLine = lines[cursorLine] ?? "";
        const inlinePrefix = extractInlineSlashPrefix(currentLine.slice(0, cursorCol));
        if (!inlinePrefix) {
          return current.getSuggestions(lines, cursorLine, cursorCol, options);
        }

        const items = skillItems(getSkills(pi), inlinePrefix.query);
        if (items.length === 0) {
          return current.getSuggestions(lines, cursorLine, cursorCol, options);
        }

        return { items, prefix: inlinePrefix.prefix };
      },

      applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
        if (!item.value.startsWith("/skill:") || !prefix.startsWith("/")) {
          return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix);
        }

        const currentLine = lines[cursorLine] ?? "";
        const beforePrefix = currentLine.slice(0, cursorCol - prefix.length);
        const afterCursor = currentLine.slice(cursorCol);
        const suffix = afterCursor.startsWith(" ") || afterCursor.startsWith("\t") ? "" : " ";
        const newLines = [...lines];
        newLines[cursorLine] = `${beforePrefix}${item.value}${suffix}${afterCursor}`;

        return {
          lines: newLines,
          cursorLine,
          cursorCol: beforePrefix.length + item.value.length + suffix.length,
        };
      },

      shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
        return current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ?? true;
      },
    }));
  });

  pi.on("input", (event, ctx) => {
    const skills = new Map(getSkills(pi).map((skill) => [skill.name, skill]));
    return transformInlineSkills(event.text, skills, formatSkillBlock, (name, error) => {
      const message = error instanceof Error ? error.message : String(error);
      ctx.ui.notify(`inline-skills: failed to load ${name}: ${message}`, "error");
    });
  });
}
