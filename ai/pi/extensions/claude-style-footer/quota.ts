import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_TIMEOUT_MS = 20_000;
const OPENAI_AUTH_CLAIM = "https://api.openai.com/auth";
const MAX_TIMESTAMP_MS = 8.64e15;

export interface RemainingQuotas {
  fiveHour?: number;
  fiveHourResetAt?: number;
  weekly?: number;
  weeklyResetAt?: number;
  accountMinimum?: boolean;
}

type UnknownRecord = Record<string, unknown>;

function asRecord(value: unknown): UnknownRecord | undefined {
  return value && typeof value === "object" ? (value as UnknownRecord) : undefined;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string" || value.trim() === "") return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function remainingPercent(window: unknown): number | undefined {
  const record = asRecord(window);
  if (!record) return undefined;

  const remaining = numberValue(record.percent_left ?? record.remaining_percent);
  if (remaining != null) return clampPercent(remaining);

  const used = numberValue(record.used_percent ?? record.percentage);
  return used == null ? undefined : clampPercent(100 - used);
}

function validTimestamp(milliseconds: number): number | undefined {
  return Number.isFinite(milliseconds) && milliseconds > 0 && milliseconds <= MAX_TIMESTAMP_MS
    ? milliseconds
    : undefined;
}

function resetAtMilliseconds(window: unknown, now: number): number | undefined {
  const record = asRecord(window);
  if (!record) return undefined;

  const resetAtValue = record.reset_at ?? record.reset_time_ms ?? record.nextResetTime;
  const numericReset = numberValue(resetAtValue);
  if (numericReset != null) {
    return validTimestamp(numericReset < 1e12 ? numericReset * 1_000 : numericReset);
  }

  if (typeof resetAtValue === "string") {
    const milliseconds = validTimestamp(Date.parse(resetAtValue));
    if (milliseconds != null) return milliseconds;
  }

  const resetAfterSeconds = numberValue(record.reset_after_seconds);
  return resetAfterSeconds == null || resetAfterSeconds < 0
    ? undefined
    : validTimestamp(now + resetAfterSeconds * 1_000);
}

export function formatTimeUntilReset(resetAt: number | undefined, now = Date.now()): string | undefined {
  if (resetAt == null || !Number.isFinite(resetAt) || !Number.isFinite(now) || resetAt <= now) {
    return undefined;
  }

  const totalSeconds = Math.ceil((resetAt - now) / 1_000);

  const days = Math.floor(totalSeconds / (24 * 60 * 60));
  const hours = Math.floor((totalSeconds % (24 * 60 * 60)) / (60 * 60));
  const minutes = Math.floor((totalSeconds % (60 * 60)) / 60);

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m`;
  return "<1m";
}

export function formatQuotaUsage(
  label: string,
  remaining: number | undefined,
  resetAt: number | undefined,
  now = Date.now(),
): string {
  const reset = formatTimeUntilReset(resetAt, now);
  return `${label}:${remaining == null ? "?" : `${Math.round(remaining)}%`}${reset ? ` (${reset})` : ""}`;
}

type QuotaWindow = "fiveHour" | "weekly";

function windowFromDuration(window: unknown): QuotaWindow | undefined {
  const seconds = numberValue(asRecord(window)?.limit_window_seconds);
  if (seconds == null || seconds <= 0) return undefined;
  if (seconds <= 6 * 60 * 60) return "fiveHour";
  if (seconds >= 6 * 24 * 60 * 60) return "weekly";
  return undefined;
}

function normalizeWindow(window: unknown, fallback: QuotaWindow): unknown {
  const record = asRecord(window);
  if (!record) return window;

  const nestedKeys =
    fallback === "fiveHour"
      ? ["primary_window", "primary", "five_hour_limit", "five_hour"]
      : ["secondary_window", "secondary", "weekly_limit", "weekly"];
  const nested = asRecord(firstValue(record, nestedKeys));
  return nested ? { ...record, ...nested } : window;
}

function assignWindow(
  quotas: RemainingQuotas,
  window: unknown,
  fallback: QuotaWindow,
  now: number,
): void {
  const normalizedWindow = normalizeWindow(window, fallback);
  const remaining = remainingPercent(normalizedWindow);
  const resetAt = resetAtMilliseconds(normalizedWindow, now);
  if (remaining == null && resetAt == null) return;

  const durationWindow = windowFromDuration(normalizedWindow);
  const target = durationWindow ?? fallback;
  const overwrite = durationWindow != null;

  if (target === "fiveHour") {
    if (remaining != null && (overwrite || quotas.fiveHour == null)) quotas.fiveHour = remaining;
    if (resetAt != null && (overwrite || quotas.fiveHourResetAt == null)) quotas.fiveHourResetAt = resetAt;
  } else {
    if (remaining != null && (overwrite || quotas.weekly == null)) quotas.weekly = remaining;
    if (resetAt != null && (overwrite || quotas.weeklyResetAt == null)) quotas.weeklyResetAt = resetAt;
  }
}

function firstValue(record: UnknownRecord, keys: string[]): unknown {
  for (const key of keys) {
    if (record[key] != null) return record[key];
  }
  return undefined;
}

export function parseRemainingQuotas(payload: unknown, now = Date.now()): RemainingQuotas {
  const response = asRecord(payload);
  if (!response) return {};

  const rateLimits = asRecord(response.rate_limit) ?? asRecord(response.rate_limits);
  if (rateLimits) {
    const quotas: RemainingQuotas = {};
    assignWindow(quotas, firstValue(rateLimits, ["five_hour_limit", "five_hour"]), "fiveHour", now);
    assignWindow(quotas, firstValue(rateLimits, ["weekly_limit", "weekly"]), "weekly", now);
    assignWindow(quotas, firstValue(rateLimits, ["primary_window", "primary"]), "fiveHour", now);
    assignWindow(quotas, firstValue(rateLimits, ["secondary_window", "secondary"]), "weekly", now);
    return quotas;
  }

  const limits = asRecord(response.data)?.limits;
  if (!Array.isArray(limits)) return {};

  const quotas: RemainingQuotas = {};
  const records = limits.map(asRecord).filter((limit): limit is UnknownRecord => limit != null);

  for (const limit of records) {
    const unitWindow = String(limit.unit) === "3" ? "fiveHour" : String(limit.unit) === "6" ? "weekly" : undefined;
    const classifiedWindow = windowFromDuration(limit) ?? unitWindow;
    if (classifiedWindow) assignWindow(quotas, limit, classifiedWindow, now);
  }

  for (const [index, limit] of records.entries()) {
    const unit = String(limit.unit);
    if (windowFromDuration(limit) || unit === "3" || unit === "6") continue;
    assignWindow(quotas, limit, index === 0 ? "fiveHour" : "weekly", now);
  }
  return quotas;
}

function mostConstrainedWindow(
  accounts: RemainingQuotas[],
  remainingKey: "fiveHour" | "weekly",
  resetKey: "fiveHourResetAt" | "weeklyResetAt",
): { remaining: number; resetAt?: number } | undefined {
  if (accounts.length === 0) return undefined;

  const windows = accounts.map((account) => ({
    remaining: account[remainingKey],
    resetAt: account[resetKey],
  }));
  if (windows.some(({ remaining }) => remaining == null || !Number.isFinite(remaining))) {
    return undefined;
  }

  const selected = windows.reduce((mostConstrained, window) =>
    window.remaining! < mostConstrained.remaining! ||
    (window.remaining === mostConstrained.remaining &&
      window.resetAt != null &&
      (mostConstrained.resetAt == null || window.resetAt < mostConstrained.resetAt))
      ? window
      : mostConstrained,
  );
  return {
    remaining: selected.remaining!,
    resetAt: Number.isFinite(selected.resetAt) ? selected.resetAt : undefined,
  };
}

export function aggregateRemainingQuotas(accounts: RemainingQuotas[]): RemainingQuotas {
  const quotas: RemainingQuotas = {};
  const fiveHour = mostConstrainedWindow(accounts, "fiveHour", "fiveHourResetAt");
  const weekly = mostConstrainedWindow(accounts, "weekly", "weeklyResetAt");

  if (fiveHour) {
    quotas.fiveHour = fiveHour.remaining;
    if (fiveHour.resetAt != null) quotas.fiveHourResetAt = fiveHour.resetAt;
  }
  if (weekly) {
    quotas.weekly = weekly.remaining;
    if (weekly.resetAt != null) quotas.weeklyResetAt = weekly.resetAt;
  }
  if (accounts.length > 1) quotas.accountMinimum = true;
  return quotas;
}

function headerValue(headers: Record<string, string> | undefined, name: string): string | undefined {
  const target = name.toLowerCase();
  for (const [key, value] of Object.entries(headers ?? {})) {
    if (key.toLowerCase() === target) return value;
  }
  return undefined;
}

function accountIdFromToken(token: string): string | undefined {
  try {
    const payload = token.split(".")[1];
    if (!payload) return undefined;
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as UnknownRecord;
    const auth = asRecord(claims[OPENAI_AUTH_CLAIM]);
    return typeof auth?.chatgpt_account_id === "string" ? auth.chatgpt_account_id : undefined;
  } catch {
    return undefined;
  }
}

async function fetchCodexQuotas(accessToken: string, accountId: string): Promise<RemainingQuotas> {
  const response = await fetch(CODEX_USAGE_URL, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "ChatGPT-Account-Id": accountId,
      Accept: "application/json",
      Origin: "https://chatgpt.com",
      Referer: "https://chatgpt.com/",
      "User-Agent": "Mozilla/5.0",
    },
    signal: AbortSignal.timeout(CODEX_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Codex usage request failed with HTTP ${response.status}`);
  return parseRemainingQuotas(await response.json());
}

interface CpaCodexCredential {
  accessToken: string;
  accountId: string;
}

function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/") || path.startsWith("~\\")) return join(homedir(), path.slice(2));
  return resolve(path);
}

function cpaAccountsDir(): string {
  return expandHome(
    process.env.CLIPROXYAPI_AUTH_DIR ??
      process.env.CLIPROXYAPI_ACCOUNTS_DIR ??
      join(homedir(), ".cli-proxy-api"),
  );
}

function errorCode(error: unknown): string | undefined {
  return error && typeof error === "object" && "code" in error
    ? String((error as { code?: unknown }).code)
    : undefined;
}

async function loadCpaCodexCredentials(): Promise<CpaCodexCredential[] | undefined> {
  const directory = cpaAccountsDir();
  let names: string[];
  try {
    names = await readdir(directory);
  } catch (error) {
    if (errorCode(error) === "ENOENT") return undefined;
    throw new Error("Could not load a complete CPA credential set", { cause: error });
  }

  const credentials: CpaCodexCredential[] = [];
  for (const name of names.filter((entry) => entry.toLowerCase().endsWith(".json"))) {
    let record: UnknownRecord | undefined;
    try {
      record = asRecord(JSON.parse(await readFile(join(directory, name), "utf8")));
    } catch (error) {
      throw new Error("Could not load a complete CPA credential set", { cause: error });
    }
    if (record?.type !== "codex" || record.disabled === true) continue;
    if (typeof record.access_token !== "string" || typeof record.account_id !== "string") {
      throw new Error("Could not load a complete CPA credential set");
    }
    credentials.push({ accessToken: record.access_token, accountId: record.account_id });
  }
  return credentials;
}

async function loadCpaCodexQuotas(): Promise<RemainingQuotas | undefined> {
  const credentials = await loadCpaCodexCredentials();
  if (credentials === undefined) return undefined;
  if (credentials.length === 0) throw new Error("Could not load a complete CPA credential set");

  const results = await Promise.allSettled(
    credentials.map((credential) => fetchCodexQuotas(credential.accessToken, credential.accountId)),
  );
  const quotas: RemainingQuotas[] = [];
  for (const result of results) {
    if (result.status === "rejected") {
      throw new Error("Could not load a complete CPA quota snapshot");
    }
    quotas.push(result.value);
  }
  return aggregateRemainingQuotas(quotas);
}

async function loadPiCodexQuotas(ctx: ExtensionContext): Promise<RemainingQuotas> {
  const model =
    ctx.model?.provider === "openai-codex"
      ? ctx.model
      : ctx.modelRegistry.getAvailable().find((candidate) => candidate.provider === "openai-codex");
  if (!model) return {};

  const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
  if (!auth.ok || !auth.apiKey) return {};

  const accountId =
    headerValue(auth.headers, "chatgpt-account-id") ?? accountIdFromToken(auth.apiKey);
  return accountId ? fetchCodexQuotas(auth.apiKey, accountId).catch(() => ({})) : {};
}

export async function loadOpenAiCodexQuotas(ctx: ExtensionContext): Promise<RemainingQuotas> {
  if (ctx.model?.provider === "cpa") {
    const cpaQuotas = await loadCpaCodexQuotas();
    if (cpaQuotas != null) return cpaQuotas;
  }
  return loadPiCodexQuotas(ctx);
}
