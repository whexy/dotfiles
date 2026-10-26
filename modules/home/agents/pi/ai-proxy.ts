import {
  getAgentDir,
  type ExtensionAPI,
  type ProviderModelConfig,
} from "@earendil-works/pi-coding-agent";
import type { Api, Model, ThinkingLevel } from "@earendil-works/pi-ai";
import {
  getBuiltinModels,
  getBuiltinProviders,
} from "@earendil-works/pi-ai/providers/all";
import { execFile } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

// Injected by Home Manager (see proxy.nix). The secret paths are agenix
// shell fragments rather than literal paths, so they are only valid inside
// a shell; `readSecret` is the single place that resolves them.
type Gateway = {
  // The provider ID pi registers the gateway under.
  id: string;
  name: string;
  baseUrl: string;
  apiKeyPath: string;
  // The gateway's Codex model catalog, whose records carry the display names
  // and limits the OpenAI-shaped list omits.
  catalogUrl: string;
  // Model IDs are `<gateway provider>/<upstream ID>`.
  qualifiedIds: boolean;
  // Without any model of the default provider, pi starts on another
  // provider's model instead, so an outage before the first successful
  // discovery registers the models pi is configured to use.
  fallbackModels: string[];
};

type AiProxyConfig = {
  gateways: Gateway[];
  cfAccessIdPath: string;
  cfAccessSecretPath: string;
  cat: string;
};

// Loading this source directly instead of the generated file leaves the config
// unset; name that cause rather than failing as a bare ReferenceError.
function loadConfig(): AiProxyConfig {
  const config = (globalThis as { __AI_PROXY_CONFIG__?: AiProxyConfig })
    .__AI_PROXY_CONFIG__;
  if (!config) {
    throw new Error(
      "ai-proxy: __AI_PROXY_CONFIG__ is unset; load the extension built by " +
        "pi/ai-proxy.nix rather than this source file.",
    );
  }
  return config;
}

const {
  gateways: GATEWAYS,
  // The gateways are published on the public internet behind Cloudflare
  // Access; without the service token every request stops at the 403 login
  // page.
  cfAccessIdPath: CF_ACCESS_ID_PATH,
  cfAccessSecretPath: CF_ACCESS_SECRET_PATH,
  cat: CAT,
} = loadConfig();

const cachePath = (gateway: Gateway) =>
  join(getAgentDir(), "cache", `${gateway.id}-model-ids.json`);

// The subset of a Codex catalog record this extension registers.
type ServedModel = {
  id: string;
  name: string;
  contextWindow?: number;
  maxTokens?: number;
  input?: Array<"text" | "image">;
  reasoningLevels?: string[];
  reasoning?: boolean;
};

// The gateways accept every one of these formats for every model they serve,
// so a catalog entry only decides which one fits the model best. Each value is
// the path under the gateway's base URL in the convention pi's client for
// that API expects.
const API_PATHS: Partial<Record<Api, string>> = {
  "openai-responses": "/v1",
  "openai-completions": "/v1",
  "anthropic-messages": "",
  "google-generative-ai": "/v1beta",
};

// Gateways in pi's catalog list the same model ID under their own API, so
// the model's vendor is consulted before them.
const VENDORS = ["anthropic", "openai", "google", "xai", "moonshotai"];

function catalogEntry(id: string): Model<Api> | undefined {
  const others = getBuiltinProviders().filter((p) => !VENDORS.includes(p));
  for (const provider of [...VENDORS, ...others]) {
    const model = getBuiltinModels(provider as never).find(
      (entry) => entry.id === id && entry.api in API_PATHS,
    );
    if (model) return model;
  }
}

const THINKING_LEVELS: ThinkingLevel[] = [
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
];

function thinkingLevelMap(
  served: ServedModel,
  entry?: Model<Api>,
): Model<Api>["thinkingLevelMap"] {
  if (!served.reasoningLevels) return entry?.thinkingLevelMap;
  const supported = new Set(served.reasoningLevels);
  const map = { ...(entry?.thinkingLevelMap ?? {}) };
  for (const level of THINKING_LEVELS) {
    if (supported.has(level)) {
      // A borrowed string is the level's wire spelling; a borrowed null
      // would veto a level the gateway declares supported.
      if (map[level] == null) map[level] = level;
      continue;
    }
    map[level] = null;
  }
  // Pi offers `off` by default, but the gateway declares the support set:
  // only an explicit "none"/"off" effort means thinking can be disabled.
  if (supported.has("none") || supported.has("off")) {
    if (map.off == null) map.off = supported.has("none") ? "none" : "off";
  } else {
    map.off = null;
  }
  return map;
}

// A model takes its API (wire format) from the entry for its upstream ID in
// pi's own catalog; its name, limits, input modalities, and the reasoning
// levels it may use come from the gateway's catalog. Models pi's catalog does
// not know use Chat Completions with the defaults pi applies to custom models
// in models.json. Extension-registered models get no such defaults, so they
// are spelled out here.
function toProxyModel(
  gateway: Gateway,
  served: ServedModel,
): ProviderModelConfig {
  const upstream = gateway.qualifiedIds
    ? served.id.slice(served.id.indexOf("/") + 1)
    : served.id;
  const entry = catalogEntry(upstream);
  if (!entry) {
    return {
      id: served.id,
      // The gateway names what it serves: gateway-only models have no entry
      // in pi's catalog, and gateways may relabel known ones.
      name: served.name,
      api: "openai-completions",
      reasoning: served.reasoning ?? false,
      thinkingLevelMap: thinkingLevelMap(served),
      input: served.input ?? ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: served.contextWindow ?? 128000,
      maxTokens: served.maxTokens ?? 16384,
    };
  }
  const { provider: _p, ...model } = entry;
  return {
    ...model,
    id: served.id,
    name: served.name,
    reasoning: served.reasoning ?? model.reasoning,
    thinkingLevelMap: thinkingLevelMap(served, entry),
    contextWindow: served.contextWindow ?? model.contextWindow,
    maxTokens: served.maxTokens ?? model.maxTokens,
    input: served.input ?? model.input,
    baseUrl: `${gateway.baseUrl}${API_PATHS[entry.api]}`,
  };
}

const execFileAsync = promisify(execFile);

// `${XDG_RUNTIME_DIR}/...` on Linux and `$(getconf ...)/...` on Darwin only
// mean anything to a shell, so read through one instead of expanding the
// fragment here and having to track agenix's platform-specific forms.
async function readSecret(path: string): Promise<string> {
  const { stdout } = await execFileAsync(
    "/bin/sh",
    ["-c", `${CAT} "${path}"`],
    {
      encoding: "utf8",
    },
  );
  const secret = stdout.trim();
  if (!secret) {
    throw new Error(`ai-proxy: secret is empty or unreadable: ${path}`);
  }
  return secret;
}

async function fetchServed(
  gateway: Gateway,
  apiKey: string,
  cfAccess: Record<string, string>,
): Promise<ServedModel[]> {
  const response = await fetch(gateway.catalogUrl, {
    headers: { Authorization: `Bearer ${apiKey}`, ...cfAccess },
    // undici strips Authorization across origins but forwards custom headers,
    // so a redirect would hand the Cloudflare Access token to whatever origin
    // it names. Refuse to follow rather than leak it.
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }

  type CatalogRecord = {
    slug?: string;
    display_name?: string;
    context_window?: number;
    max_tokens?: number;
    input_modalities?: string[];
    supported_reasoning_levels?: Array<{ effort?: string }>;
    visibility?: string;
  };
  const payload = (await response.json()) as { models?: CatalogRecord[] };
  if (!Array.isArray(payload.models)) {
    throw new Error("catalog returned no model list");
  }
  const seen = new Set<string>();
  const served: ServedModel[] = [];
  for (const record of payload.models) {
    const id = record?.slug;
    // Codex owns `visibility`: "hide" marks non-chat models (TTS, image
    // generation) that do not belong in a model picker.
    if (
      typeof id !== "string" ||
      id.length === 0 ||
      seen.has(id) ||
      record.visibility === "hide"
    )
      continue;
    seen.add(id);
    const input = Array.isArray(record.input_modalities)
      ? record.input_modalities.filter(
          (modality): modality is "text" | "image" =>
            modality === "text" || modality === "image",
        )
      : undefined;
    const reasoningLevels = Array.isArray(record.supported_reasoning_levels)
      ? [
          ...new Set(
            record.supported_reasoning_levels.flatMap((level) =>
              typeof level?.effort === "string" && level.effort
                ? [level.effort]
                : [],
            ),
          ),
        ]
      : undefined;
    served.push({
      id,
      name:
        typeof record.display_name === "string" && record.display_name
          ? record.display_name
          : id,
      contextWindow:
        typeof record.context_window === "number"
          ? record.context_window
          : undefined,
      maxTokens:
        typeof record.max_tokens === "number" ? record.max_tokens : undefined,
      input: input && input.length > 0 ? input : undefined,
      reasoningLevels,
      reasoning:
        reasoningLevels === undefined ? undefined : reasoningLevels.length > 0,
    });
  }
  return served;
}

async function discoverServed(gateway: Gateway): Promise<ServedModel[]> {
  const [apiKey, cfAccessId, cfAccessSecret] = await Promise.all([
    readSecret(gateway.apiKeyPath),
    readSecret(CF_ACCESS_ID_PATH),
    readSecret(CF_ACCESS_SECRET_PATH),
  ]);
  return fetchServed(gateway, apiKey, {
    "CF-Access-Client-Id": cfAccessId,
    "CF-Access-Client-Secret": cfAccessSecret,
  });
}

async function readCached(
  gateway: Gateway,
): Promise<ServedModel[] | undefined> {
  try {
    const cached = JSON.parse(
      await readFile(cachePath(gateway), "utf8"),
    ) as unknown;
    if (Array.isArray(cached)) {
      // Caches written before display names hold bare IDs.
      if (cached.every((id) => typeof id === "string")) {
        return (cached as string[]).map((id) => ({ id, name: id }));
      }
      if (
        cached.every(
          (model) =>
            typeof model === "object" &&
            model !== null &&
            typeof (model as { id?: unknown }).id === "string" &&
            typeof (model as { name?: unknown }).name === "string",
        )
      ) {
        return cached as ServedModel[];
      }
    }
  } catch {
    // An absent or unreadable cache is the same as none.
  }
  return undefined;
}

// Concurrent pi processes each rename a complete file into place.
async function writeCached(
  gateway: Gateway,
  served: ServedModel[],
): Promise<void> {
  const path = cachePath(gateway);
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(served)}\n`, "utf8");
  await rename(temporaryPath, path);
}

async function registerGateway(
  pi: ExtensionAPI,
  gateway: Gateway,
): Promise<void> {
  let served: ServedModel[];
  try {
    served = await discoverServed(gateway);
    // A cache that cannot be written only costs the next outage its list.
    await writeCached(gateway, served).catch(() => {});
  } catch (error) {
    // Pi exits when an extension fails to load, so a brief gateway outage
    // must fall back instead of throwing.
    const cached = await readCached(gateway);
    served = cached ?? gateway.fallbackModels.map((id) => ({ id, name: id }));
    const reason = error instanceof Error ? error.message : String(error);
    const notice =
      `${gateway.name} model list unavailable (${reason}); ` +
      (cached
        ? "using the last list it served"
        : served.length > 0
          ? "using the configured default models"
          : "none of its models are available");
    const unsubscribe = pi.on("session_start", (_event, ctx) => {
      unsubscribe();
      if (ctx.hasUI) ctx.ui.notify(notice, "warning");
    });
  }
  if (served.length === 0) return;

  pi.registerProvider(gateway.id, {
    name: gateway.name,
    baseUrl: `${gateway.baseUrl}/v1`,
    // pi runs `!` values through a shell and resolves them per request, so
    // the agenix path expands and a re-decrypted token is picked up without
    // restarting the session. The double quotes are what make it expand.
    apiKey: `!${CAT} "${gateway.apiKeyPath}"`,
    headers: {
      "CF-Access-Client-Id": `!${CAT} "${CF_ACCESS_ID_PATH}"`,
      "CF-Access-Client-Secret": `!${CAT} "${CF_ACCESS_SECRET_PATH}"`,
    },
    models: served.map((model) => toProxyModel(gateway, model)),
  });
}

export default async function (pi: ExtensionAPI) {
  await Promise.all(GATEWAYS.map((gateway) => registerGateway(pi, gateway)));
}
