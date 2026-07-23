const INLINE_SKILL_PATTERN = /(^|\s)\/skill:([a-z0-9-]+)(?=$|\s)/g;

export type InlineSkillTransformResult =
  | { action: "continue" }
  | { action: "transform"; text: string };

export function transformInlineSkills<T>(
  text: string,
  skills: ReadonlyMap<string, T>,
  formatSkill: (skill: T) => string,
  onError: (name: string, error: unknown) => void,
): InlineSkillTransformResult {
  const failedSkills = new Set<string>();
  let changed = false;

  const transformed = text.replace(
    INLINE_SKILL_PATTERN,
    (original, boundary: string, name: string, matchOffset: number) => {
      const invocationOffset = matchOffset + boundary.length;
      if (invocationOffset === 0) return original;

      const skill = skills.get(name);
      if (!skill) return original;

      try {
        const block = formatSkill(skill);
        changed = true;
        return `${boundary}${block}`;
      } catch (error) {
        if (!failedSkills.has(name)) {
          failedSkills.add(name);
          onError(name, error);
        }
        return original;
      }
    },
  );

  return changed ? { action: "transform", text: transformed } : { action: "continue" };
}
