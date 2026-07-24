import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";
import { basename } from "node:path";

import { formatTimeUntilReset, loadOpenAiCodexQuotas } from "./quota.ts";

const GIT_REFRESH_MS = 10_000;
const PULL_REQUEST_REFRESH_MS = 60_000;
const QUOTA_REFRESH_MS = 5 * 60_000;
const RUNTIME_ENTRY_TYPE = "claude-style-footer:agent-runtime";

interface GitChanges {
  additions: number;
  deletions: number;
  untracked: number;
  dirty: boolean;
}

interface PullRequest {
  number: number;
  url: string;
}

function terminalLink(text: string, url: string): string {
  return `\x1b]8;;${url}\x1b\\${text}\x1b]8;;\x1b\\`;
}

function formatTokens(tokens: number): string {
  if (tokens < 1_000) return `${tokens}`;
  return `${Math.floor(tokens / 1_000)}k`;
}

function shortModelName(name: string): string {
  return name.replace(/^Claude\s+/i, "");
}

function formatAgentRuntime(milliseconds: number): string {
  const totalSeconds = Math.floor(milliseconds / 1_000);
  const hours = Math.floor(totalSeconds / 3_600);
  const minutes = Math.floor((totalSeconds % 3_600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

async function resolveProjectName(pi: ExtensionAPI, cwd: string): Promise<string> {
  const result = await pi.exec("git", ["worktree", "list", "--porcelain"], { cwd, timeout: 5_000 }).catch(
    () => undefined,
  );
  const mainWorktree = result?.stdout
    .split("\n")
    .find((line) => line.startsWith("worktree "))
    ?.slice("worktree ".length);
  return basename(mainWorktree || cwd);
}

function usageCost(usage: unknown): number {
  if (!usage || typeof usage !== "object") return 0;
  const total = (usage as { cost?: { total?: unknown } }).cost?.total;
  return typeof total === "number" && Number.isFinite(total) ? total : 0;
}

export function calculateSessionCost(ctx: ExtensionContext): number {
  let cost = 0;

  for (const entry of ctx.sessionManager.getEntries()) {
    const usageEntry = entry as {
      type: string;
      message?: { role?: string; usage?: unknown };
      usage?: unknown;
    };

    if (
      usageEntry.type === "message" &&
      (usageEntry.message?.role === "assistant" || usageEntry.message?.role === "toolResult")
    ) {
      cost += usageCost(usageEntry.message.usage);
    } else if (usageEntry.type === "compaction" || usageEntry.type === "branch_summary") {
      cost += usageCost(usageEntry.usage);
    }
  }

  return cost;
}

interface AgentRuntime {
  totalMs: number;
  latestTurnMs: number;
}

function loadAgentRuntime(ctx: ExtensionContext): AgentRuntime {
  const runtime: AgentRuntime = { totalMs: 0, latestTurnMs: 0 };
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "custom" || entry.customType !== RUNTIME_ENTRY_TYPE) continue;
    const data = entry.data as { totalMs?: unknown; latestTurnMs?: unknown } | undefined;
    if (typeof data?.totalMs === "number" && Number.isFinite(data.totalMs) && data.totalMs >= 0) {
      runtime.totalMs = data.totalMs;
    }
    if (
      typeof data?.latestTurnMs === "number" &&
      Number.isFinite(data.latestTurnMs) &&
      data.latestTurnMs >= 0
    ) {
      runtime.latestTurnMs = data.latestTurnMs;
    }
  }
  return runtime;
}

export default function (pi: ExtensionAPI) {
  let requestFooterRender: (() => void) | undefined;
  let totalAgentRuntimeMs = 0;
  let latestTurnRuntimeMs = 0;
  let activeAgentStartedAt: number | undefined;

  const currentAgentRuntime = () =>
    totalAgentRuntimeMs + (activeAgentStartedAt == null ? 0 : performance.now() - activeAgentStartedAt);
  const currentTurnRuntime = () =>
    activeAgentStartedAt == null ? latestTurnRuntimeMs : performance.now() - activeAgentStartedAt;

  pi.on("agent_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    activeAgentStartedAt ??= performance.now();
    requestFooterRender?.();
  });

  pi.on("agent_settled", (_event, ctx) => {
    if (ctx.mode !== "tui" || activeAgentStartedAt == null) return;
    const settledAt = performance.now();
    latestTurnRuntimeMs = settledAt - activeAgentStartedAt;
    totalAgentRuntimeMs += latestTurnRuntimeMs;
    activeAgentStartedAt = ctx.isIdle() ? undefined : settledAt;
    pi.appendEntry(RUNTIME_ENTRY_TYPE, {
      totalMs: totalAgentRuntimeMs,
      latestTurnMs: latestTurnRuntimeMs,
    });
    requestFooterRender?.();
  });

  pi.on("session_tree", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    const runtime = loadAgentRuntime(ctx);
    totalAgentRuntimeMs = runtime.totalMs;
    latestTurnRuntimeMs = runtime.latestTurnMs;
    activeAgentStartedAt = undefined;
    requestFooterRender?.();
  });

  pi.on("session_start", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    const [versionResult, projectName] = await Promise.all([
      pi.exec("pi", ["--version"], { timeout: 5_000 }).catch(() => undefined),
      resolveProjectName(pi, ctx.cwd),
    ]);
    const piVersion = versionResult?.stdout.trim() || "unknown";
    const runtime = loadAgentRuntime(ctx);
    totalAgentRuntimeMs = runtime.totalMs;
    latestTurnRuntimeMs = runtime.latestTurnMs;
    activeAgentStartedAt = undefined;
    ctx.ui.setFooter((tui, theme, footerData) => {
      let disposed = false;
      let gitChanges: GitChanges = { additions: 0, deletions: 0, untracked: 0, dirty: false };
      let pullRequest: PullRequest | undefined;
      let pullRequestRequestId = 0;
      let fiveHourQuota: number | undefined;
      let fiveHourResetAt: number | undefined;
      let weeklyQuota: number | undefined;
      let weeklyResetAt: number | undefined;

      const requestRender = () => {
        if (!disposed) tui.requestRender();
      };
      requestFooterRender = requestRender;

      const refreshGit = async () => {
        const [statusResult, diffResult] = await Promise.all([
          pi.exec("git", ["status", "--porcelain=v1"], { cwd: ctx.cwd, timeout: 5_000 }).catch(() => undefined),
          pi.exec("git", ["diff", "--numstat", "HEAD", "--"], { cwd: ctx.cwd, timeout: 5_000 }).catch(
            () => undefined,
          ),
        ]);

        if (statusResult?.code !== 0) {
          gitChanges = { additions: 0, deletions: 0, untracked: 0, dirty: false };
          requestRender();
          return;
        }

        const statusLines = statusResult.stdout.split("\n").filter(Boolean);
        const untracked = statusLines.filter((line) => line.startsWith("?? ")).length;
        let additions = 0;
        let deletions = 0;

        if (diffResult?.code === 0) {
          for (const line of diffResult.stdout.split("\n")) {
            const [added, removed] = line.split("\t");
            if (added && added !== "-") additions += Number.parseInt(added, 10) || 0;
            if (removed && removed !== "-") deletions += Number.parseInt(removed, 10) || 0;
          }
        }

        gitChanges = {
          additions,
          deletions,
          untracked,
          dirty: statusLines.length > 0,
        };
        requestRender();
      };

      const refreshPullRequest = async () => {
        const requestId = ++pullRequestRequestId;
        const branchName = footerData.getGitBranch();
        if (!branchName || branchName === "detached") {
          pullRequest = undefined;
          requestRender();
          return;
        }

        const result = await pi
          .exec("gh", ["pr", "view", branchName, "--json", "number,url"], {
            cwd: ctx.cwd,
            timeout: 10_000,
          })
          .catch(() => undefined);
        if (disposed || requestId !== pullRequestRequestId) return;

        try {
          const parsed = JSON.parse(result?.stdout ?? "") as Partial<PullRequest>;
          pullRequest =
            result?.code === 0 && Number.isInteger(parsed.number) && typeof parsed.url === "string"
              ? { number: parsed.number!, url: parsed.url }
              : undefined;
        } catch {
          pullRequest = undefined;
        }
        requestRender();
      };

      const refreshQuota = async () => {
        const quotas = await loadOpenAiCodexQuotas(ctx).catch(() => ({}));
        fiveHourQuota = quotas.fiveHour;
        fiveHourResetAt = quotas.fiveHourResetAt;
        weeklyQuota = quotas.weekly;
        weeklyResetAt = quotas.weeklyResetAt;
        requestRender();
      };

      const branchUnsubscribe = footerData.onBranchChange(() => {
        pullRequest = undefined;
        requestRender();
        void refreshPullRequest();
      });
      const gitTimer = setInterval(() => void refreshGit(), GIT_REFRESH_MS);
      const pullRequestTimer = setInterval(() => void refreshPullRequest(), PULL_REQUEST_REFRESH_MS);
      const quotaTimer = setInterval(() => void refreshQuota(), QUOTA_REFRESH_MS);
      const runtimeTimer = setInterval(() => {
        if (activeAgentStartedAt != null) requestRender();
      }, 1_000);
      void refreshGit();
      void refreshPullRequest();
      void refreshQuota();

      return {
        dispose() {
          disposed = true;
          requestFooterRender = undefined;
          clearInterval(gitTimer);
          clearInterval(pullRequestTimer);
          clearInterval(quotaTimer);
          clearInterval(runtimeTimer);
          branchUnsubscribe();
        },
        invalidate() {},
        render(width: number): string[] {
          const modelName = shortModelName(ctx.model?.name ?? ctx.model?.id ?? "no model");
          const thinking = pi.getThinkingLevel();
          const model = thinking === "off" ? modelName : `${modelName} (${thinking})`;

          const usage = ctx.getContextUsage();
          const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow;
          const contextTokens = usage?.tokens ?? 0;
          const contextPercent = usage?.percent == null ? 0 : Math.round(usage.percent);
          const context = `ctx:${contextPercent}% (${formatTokens(contextTokens)}/${formatTokens(contextWindow ?? 0)})`;

          const branchName = footerData.getGitBranch() ?? "no-git";
          const branchParts = [theme.fg("success", branchName)];
          if (pullRequest) {
            branchParts.push(
              theme.fg("dim", "·"),
              terminalLink(theme.fg("success", `#${pullRequest.number}`), pullRequest.url),
            );
          }
          if (gitChanges.additions > 0) branchParts.push(theme.fg("success", `+${gitChanges.additions}`));
          if (gitChanges.deletions > 0) branchParts.push(theme.fg("error", `-${gitChanges.deletions}`));
          if (gitChanges.untracked > 0) branchParts.push(theme.fg("warning", `?${gitChanges.untracked}`));
          if (
            gitChanges.dirty &&
            gitChanges.additions === 0 &&
            gitChanges.deletions === 0 &&
            gitChanges.untracked === 0
          ) {
            branchParts.push(theme.fg("warning", "*"));
          }
          const branch = branchParts.join(" ");
          const agentRuntime =
            `agent:${formatAgentRuntime(currentAgentRuntime())}` +
            ` · turn:${formatAgentRuntime(currentTurnRuntime())}`;
          const sessionCost = calculateSessionCost(ctx);
          const fiveHourReset = formatTimeUntilReset(fiveHourResetAt);
          const weeklyReset = formatTimeUntilReset(weeklyResetAt);
          const fiveHourUsage = `5h:${fiveHourQuota == null ? "?" : `${Math.round(fiveHourQuota)}%`}${fiveHourReset ? ` (${fiveHourReset})` : ""}`;
          const weeklyUsage = `week:${weeklyQuota == null ? "?" : `${Math.round(weeklyQuota)}%`}${weeklyReset ? ` (${weeklyReset})` : ""}`;
          const quota = `${fiveHourUsage} ${weeklyUsage} left`;

          const segments = [
            theme.fg("error", model),
            theme.fg("bashMode", `pi v${piVersion}`),
            theme.fg("warning", context),
            branch,
            theme.fg("mdCode", projectName),
            theme.fg("syntaxFunction", agentRuntime),
            theme.fg("dim", `$${sessionCost.toFixed(3)} · ${quota}`),
          ];

          const extensionStatuses = [...footerData.getExtensionStatuses().values()].filter(Boolean);
          if (extensionStatuses.length > 0) {
            segments.push(theme.fg("syntaxNumber", extensionStatuses.join(", ")));
          }

          return [truncateToWidth(segments.join(theme.fg("dim", " | ")), width)];
        },
      };
    });
  });
}
