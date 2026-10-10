// Pi extension: measure the token generation speed of the current model.
//
// Nothing shows until `/tokenspeed on`. Then the terminal UI gets a footer
// status line with the live output speed while a response streams and the
// final speed of the last message afterwards, and RPC clients such as T3 Code
// get one notification per run with the run's average speed. `/tokenspeed off`
// hides them again, `/tokenspeed` prints per-model session aggregates and
// recent per-message speeds, and `/tokenspeed reset` clears the statistics.
//
// Speed = output tokens / streaming time (first delta to message end), so
// time-to-first-token is excluded for streams measured live. Messages
// reconstructed from a resumed session only carry the provider-request wall
// time, which includes TTFT and therefore reads slightly low. Speeds computed
// from a character heuristic instead of provider-reported token counts are
// marked ~.
import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

interface StreamState {
  startedAt: number;
  // undefined until the first output delta arrives
  firstDeltaAt: number | undefined;
  lastDeltaAt: number | undefined;
  charsTotal: number;
  // CJK characters tokenize at roughly one token per character for most
  // large-model tokenizers; the rest averages about four characters.
  cjkChars: number;
  // provider-reported output tokens so far; 0 until a usage delta arrives
  reportedTokens: number;
  // once any provider-reported output count is seen, the char estimate retires
  reportedSeen: boolean;
}

interface MessageRecord {
  provider: string;
  model: string;
  tokens: number;
  // true when the token count came from provider usage rather than the char estimate
  exact: boolean;
  streamMs: number;
  ttftMs: number | undefined;
}

interface ModelAggregate {
  tokens: number;
  streamMs: number;
  ttftMs: number;
  ttftCount: number;
  messages: number;
}

function estimateTokens(charsTotal: number, cjkChars: number): number {
  return cjkChars + Math.ceil((charsTotal - cjkChars) / 4);
}

function fmtTokens(n: number): string {
  if (n < 1000) return String(Math.round(n));
  if (n < 10000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1000000) return `${Math.round(n / 1000)}k`;
  if (n < 10000000) return `${(n / 1000000).toFixed(1)}M`;
  return `${Math.round(n / 1000000)}M`;
}

function fmtSeconds(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return "0s";
  if (ms < 10000) return `${(ms / 1000).toFixed(1)}s`;
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

function recordSpeed(r: MessageRecord): number {
  return r.exact && r.streamMs > 0 ? r.tokens / (r.streamMs / 1000) : 0;
}

const MAX_RECENT = 10;
// Skip speeds computed over a smaller window; a stream that finishes this
// fast says more about queueing than about generation speed.
const MIN_STREAM_MS = 200;
const CJK_RE =
  /[\u2e80-\u9fff\uf900-\ufaff\u3000-\u303f\uac00-\ud7af\uff00-\uffef]/g;
// The toggle outlives sessions and reloads. Home Manager owns settings.json
// as a read-only store link, so it lives in a file of its own.
const PREFS_PATH = join(getAgentDir(), "token-speed.json");

async function loadEnabled(): Promise<boolean> {
  try {
    const prefs = JSON.parse(await readFile(PREFS_PATH, "utf8")) as {
      enabled?: unknown;
    };
    return prefs.enabled === true;
  } catch {
    return false;
  }
}

export default function (pi: ExtensionAPI) {
  // One assistant message streams at a time in the agent loop; message events
  // do not carry the same object identity across message_start/update/end, so
  // state is a singleton for the stream in flight instead of a per-message map.
  let current: StreamState | undefined;
  const aggregates = new Map<string, ModelAggregate>();
  const recent: MessageRecord[] = [];
  // Model whose measured output landed last; anchors the report headline.
  let lastProvider: string | undefined;
  let lastModel: string | undefined;
  let enabled = false;
  // Latest footer text, kept while the footer is hidden so enabling it shows
  // the last measurement at once.
  let footer: string | undefined;
  // Exact measurements of the run in flight, summarized when it settles.
  let run = { tokens: 0, streamMs: 0, messages: 0 };

  function addRecord(record: MessageRecord) {
    recent.push(record);
    if (recent.length > MAX_RECENT) recent.shift();

    if (!record.exact) return;
    const key = `${record.provider}/${record.model}`;
    let agg = aggregates.get(key);
    if (!agg) {
      agg = { tokens: 0, streamMs: 0, ttftMs: 0, ttftCount: 0, messages: 0 };
      aggregates.set(key, agg);
    }
    agg.tokens += record.tokens;
    agg.streamMs += record.streamMs;
    if (record.ttftMs != null) {
      agg.ttftMs += record.ttftMs;
      agg.ttftCount++;
    }
    agg.messages++;
    lastProvider = record.provider;
    lastModel = record.model;
  }

  function footerText(
    state: StreamState | undefined,
    record: MessageRecord | undefined,
  ): string | undefined {
    if (state && state.firstDeltaAt != null) {
      const elapsed =
        (state.lastDeltaAt ?? state.firstDeltaAt) - state.firstDeltaAt;
      const tokens = state.reportedSeen
        ? state.reportedTokens
        : estimateTokens(state.charsTotal, state.cjkChars);
      if (elapsed < MIN_STREAM_MS || tokens <= 0) return undefined;
      const speed = tokens / (elapsed / 1000);
      return `⚡ ${state.reportedSeen ? "" : "~"}${speed.toFixed(1)} tok/s · ${fmtTokens(tokens)} tok`;
    }
    if (record && recordSpeed(record) > 0) {
      return `⚡ ${recordSpeed(record).toFixed(1)} tok/s · ${fmtTokens(record.tokens)} tok · ${fmtSeconds(record.streamMs)}`;
    }
    return undefined;
  }

  function setFooter(text: string | undefined, ctx: ExtensionContext) {
    footer = text;
    showFooter(ctx);
  }

  function showFooter(ctx: ExtensionContext) {
    // RPC clients get the per-run summary instead; T3 Code drops status updates.
    if (ctx.mode !== "tui") return;
    ctx.ui.setStatus("token-speed", enabled ? footer : undefined);
  }

  function freshState(startedAt: number): StreamState {
    return {
      startedAt,
      firstDeltaAt: undefined,
      lastDeltaAt: undefined,
      charsTotal: 0,
      cjkChars: 0,
      reportedTokens: 0,
      reportedSeen: false,
    };
  }

  pi.on("message_start", (event) => {
    const message = event.message;
    if (message.role !== "assistant") return;
    current = freshState(Date.now());
    current.reportedTokens = message.usage?.output ?? 0;
  });

  pi.on("message_update", (event, ctx) => {
    const ev = event.assistantMessageEvent;
    if (
      ev.type !== "text_delta" &&
      ev.type !== "thinking_delta" &&
      ev.type !== "toolcall_delta"
    )
      return;
    if (event.message.role !== "assistant") return;
    current ??= freshState(Date.now());
    const state = current;
    // message_start may predate a mid-stream reload, hence the lazy seed.
    state.charsTotal += ev.delta.length;
    const cjk = ev.delta.match(CJK_RE);
    if (cjk) state.cjkChars += cjk.length;
    const now = Date.now();
    if (state.firstDeltaAt == null) state.firstDeltaAt = now;
    state.lastDeltaAt = now;
    const reported = event.message.usage?.output ?? 0;
    if (reported > state.reportedTokens) {
      state.reportedTokens = reported;
      state.reportedSeen = true;
    }
    setFooter(footerText(state, undefined), ctx);
  });

  pi.on("message_end", (event, ctx) => {
    if (event.message.role !== "assistant") return;
    const state = current;
    current = undefined;
    if (!state) return;
    const message = event.message;
    const streamMs =
      state.firstDeltaAt != null
        ? (state.lastDeltaAt ?? Date.now()) - state.firstDeltaAt
        : 0;
    const reported = message.usage?.output ?? 0;
    const record: MessageRecord = {
      provider: message.provider,
      model: message.model,
      tokens:
        reported > 0
          ? reported
          : estimateTokens(state.charsTotal, state.cjkChars),
      exact: reported > 0,
      streamMs,
      ttftMs:
        state.firstDeltaAt != null
          ? state.firstDeltaAt - state.startedAt
          : undefined,
    };
    if (streamMs >= MIN_STREAM_MS && record.tokens > 0) {
      addRecord(record);
      if (record.exact) {
        run.tokens += record.tokens;
        run.streamMs += record.streamMs;
        run.messages++;
      }
    }
    setFooter(footerText(undefined, record), ctx);
  });

  // T3 Code shows notifications in the thread only while a turn is active,
  // which it still is before the run settles.
  pi.on("agent_before_settle", (_event, ctx) => {
    const { tokens, streamMs, messages } = run;
    run = { tokens: 0, streamMs: 0, messages: 0 };
    if (!enabled || ctx.mode !== "rpc" || streamMs <= 0) return;
    ctx.ui.notify(
      `⚡ ${(tokens / (streamMs / 1000)).toFixed(1)} tok/s · ${fmtTokens(tokens)} tok · ${fmtSeconds(streamMs)} · ${plural(messages, "msg")}`,
      "info",
    );
  });

  pi.registerCommand("tokenspeed", {
    description: "Show measured model token speeds; on/off toggles the display",
    getArgumentCompletions: (prefix) => {
      const matches = ["on", "off", "reset"]
        .filter((arg) => arg.startsWith(prefix))
        .map((arg) => ({ value: arg, label: arg }));
      return matches.length > 0 ? matches : null;
    },
    handler: async (args, ctx) => {
      const arg = args.trim();
      if (arg === "on" || arg === "off") {
        enabled = arg === "on";
        showFooter(ctx);
        await writeFile(PREFS_PATH, `${JSON.stringify({ enabled })}\n`);
        ctx.ui.notify(
          `Token speed display ${enabled ? "enabled" : "disabled"}`,
          "info",
        );
        return;
      }
      if (arg === "reset") {
        aggregates.clear();
        recent.length = 0;
        lastProvider = undefined;
        lastModel = undefined;
        run = { tokens: 0, streamMs: 0, messages: 0 };
        setFooter(undefined, ctx);
        ctx.ui.notify("Token speed statistics reset", "info");
        return;
      }
      ctx.ui.notify(renderReport(), "info");
    },
  });

  function renderReport(): string {
    const lines: string[] = [];

    const current =
      lastProvider != null && lastModel != null
        ? aggregates.get(`${lastProvider}/${lastModel}`)
        : undefined;
    if (lastProvider != null && lastModel != null && current != null) {
      const avg =
        current.streamMs > 0 ? current.tokens / (current.streamMs / 1000) : 0;
      lines.push(
        `${lastProvider}/${lastModel}: ${avg.toFixed(1)} tok/s avg · ${plural(current.messages, "msg")} · ${fmtTokens(current.tokens)} tok · ${fmtSeconds(current.streamMs)} streaming`,
      );
      if (current.ttftCount > 0) {
        lines.push(
          `TTFT ${(current.ttftMs / current.ttftCount / 1000).toFixed(1)}s avg`,
        );
      }
    }

    if (aggregates.size > 1) {
      lines.push("models this session:");
      for (const [key, agg] of aggregates) {
        const avg = agg.streamMs > 0 ? agg.tokens / (agg.streamMs / 1000) : 0;
        lines.push(
          `  ${key}  ${avg.toFixed(1).padStart(6)} tok/s  ↑${fmtTokens(agg.tokens).padStart(7)} tok  ${plural(agg.messages, "msg")}`,
        );
      }
    }

    if (recent.length > 0) {
      lines.push("last messages:");
      for (const r of recent) {
        lines.push(
          `  ${r.exact ? "" : "~"}${recordSpeed(r).toFixed(1).padStart(5)} tok/s  ↑${fmtTokens(r.tokens).padStart(6)} tok in ${fmtSeconds(r.streamMs).padStart(6)}  ${r.provider}/${r.model}`,
        );
      }
    }

    if (recoveredFromHistory) {
      lines.push(
        "resumed messages measure the full provider request, TTFT included",
      );
    }

    if (lines.length === 0) return "No completed message stream measured yet.";
    return lines.join("\n");
  }

  let recoveredFromHistory = false;

  pi.on("session_start", async (_event, ctx) => {
    // Another pi process may have toggled the footer since this one loaded.
    enabled = await loadEnabled();
    showFooter(ctx);
    // Rebuild from the active branch so stats survive reloads and resumes.
    aggregates.clear();
    recent.length = 0;
    lastProvider = undefined;
    lastModel = undefined;
    recoveredFromHistory = false;
    run = { tokens: 0, streamMs: 0, messages: 0 };
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "message") continue;
      const message = (entry as { message?: unknown }).message as
        | {
            role?: string;
            provider?: string;
            model?: string;
            usage?: { output?: number };
            durationMs?: number;
          }
        | undefined;
      if (message?.role !== "assistant") continue;
      const tokens = message.usage?.output ?? 0;
      // durationMs spans the whole provider request, TTFT included; the
      // persisted message has no per-delta timeline to subtract it from.
      if (
        tokens <= 0 ||
        message.durationMs == null ||
        !Number.isFinite(message.durationMs)
      )
        continue;
      if (message.provider == null || message.model == null) continue;
      recoveredFromHistory = true;
      addRecord({
        provider: message.provider,
        model: message.model,
        tokens,
        exact: true,
        streamMs: message.durationMs,
        ttftMs: undefined,
      });
    }
  });
}
