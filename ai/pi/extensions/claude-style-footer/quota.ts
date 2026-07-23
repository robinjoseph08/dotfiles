import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

const CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_TIMEOUT_MS = 20_000;
const OPENAI_AUTH_CLAIM = "https://api.openai.com/auth";

export interface RemainingQuotas {
  fiveHour?: number;
  weekly?: number;
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

type QuotaWindow = "fiveHour" | "weekly";

function windowFromDuration(window: unknown): QuotaWindow | undefined {
  const seconds = numberValue(asRecord(window)?.limit_window_seconds);
  if (seconds == null) return undefined;
  return seconds <= 24 * 60 * 60 ? "fiveHour" : "weekly";
}

function assignWindow(
  quotas: RemainingQuotas,
  window: unknown,
  fallback: QuotaWindow,
): void {
  const remaining = remainingPercent(window);
  if (remaining == null) return;

  const durationWindow = windowFromDuration(window);
  if (durationWindow) {
    quotas[durationWindow] = remaining;
  } else {
    quotas[fallback] ??= remaining;
  }
}

function firstValue(record: UnknownRecord, keys: string[]): unknown {
  for (const key of keys) {
    if (record[key] != null) return record[key];
  }
  return undefined;
}

export function parseRemainingQuotas(payload: unknown): RemainingQuotas {
  const response = asRecord(payload);
  if (!response) return {};

  const rateLimits = asRecord(response.rate_limit) ?? asRecord(response.rate_limits);
  if (rateLimits) {
    const quotas: RemainingQuotas = {};
    assignWindow(quotas, firstValue(rateLimits, ["five_hour_limit", "five_hour"]), "fiveHour");
    assignWindow(quotas, firstValue(rateLimits, ["weekly_limit", "weekly"]), "weekly");
    assignWindow(quotas, firstValue(rateLimits, ["primary_window", "primary"]), "fiveHour");
    assignWindow(quotas, firstValue(rateLimits, ["secondary_window", "secondary"]), "weekly");
    return quotas;
  }

  const limits = asRecord(response.data)?.limits;
  if (!Array.isArray(limits)) return {};

  const quotas: RemainingQuotas = {};
  const records = limits.map(asRecord).filter((limit): limit is UnknownRecord => limit != null);

  for (const limit of records) {
    const unitWindow = String(limit.unit) === "3" ? "fiveHour" : String(limit.unit) === "6" ? "weekly" : undefined;
    const classifiedWindow = windowFromDuration(limit) ?? unitWindow;
    const remaining = remainingPercent(limit);
    if (classifiedWindow && remaining != null) quotas[classifiedWindow] = remaining;
  }

  for (const [index, limit] of records.entries()) {
    const unit = String(limit.unit);
    if (windowFromDuration(limit) || unit === "3" || unit === "6") continue;
    assignWindow(quotas, limit, index === 0 ? "fiveHour" : "weekly");
  }
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

export async function loadOpenAiCodexQuotas(ctx: ExtensionContext): Promise<RemainingQuotas> {
  const model =
    ctx.model?.provider === "openai-codex"
      ? ctx.model
      : ctx.modelRegistry.getAvailable().find((candidate) => candidate.provider === "openai-codex");
  if (!model) return {};

  const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
  if (!auth.ok || !auth.apiKey) return {};

  const accountId =
    headerValue(auth.headers, "chatgpt-account-id") ?? accountIdFromToken(auth.apiKey);
  if (!accountId) return {};

  const response = await fetch(CODEX_USAGE_URL, {
    headers: {
      Authorization: `Bearer ${auth.apiKey}`,
      "ChatGPT-Account-Id": accountId,
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(CODEX_TIMEOUT_MS),
  });
  if (!response.ok) return {};

  return parseRemainingQuotas(await response.json());
}
