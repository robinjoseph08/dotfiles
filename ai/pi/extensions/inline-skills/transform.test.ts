import assert from "node:assert/strict";
import test from "node:test";

import { transformInlineSkills } from "./transform.ts";

const skills = new Map([
  ["alpha", "ALPHA"],
  ["beta", "BETA"],
]);
const format = (skill: string): string => `<${skill}>`;

test("leaves a prompt-start skill for Pi native handling", () => {
  assert.deepEqual(transformInlineSkills("/skill:alpha", skills, format, () => {}), {
    action: "continue",
  });
});

test("expands inline skills without expanding a prompt-start skill", () => {
  assert.deepEqual(
    transformInlineSkills("/skill:alpha then /skill:beta now", skills, format, () => {}),
    { action: "transform", text: "/skill:alpha then <BETA> now" },
  );
});

test("leaves escaped and unknown skills unchanged", () => {
  assert.deepEqual(
    transformInlineSkills("Use \\/skill:alpha and /skill:missing", skills, format, () => {}),
    { action: "continue" },
  );
});

test("reports a failed skill once without transforming it", () => {
  const failures: string[] = [];
  const result = transformInlineSkills(
    "Use /skill:alpha then /skill:alpha",
    skills,
    () => {
      throw new Error("unreadable");
    },
    (name) => failures.push(name),
  );

  assert.deepEqual(result, { action: "continue" });
  assert.deepEqual(failures, ["alpha"]);
});
