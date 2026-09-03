import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const BASE_URL = "https://ai-proxy.at-basking.ts.net/v1";
const MODELS_DEV_URL = "https://models.dev/api.json";
const API_KEY_PATH = join(process.env.HOME!, ".secrets", "ai-proxy-api-key");
const AGENT_DIR =
  process.env.PI_CODING_AGENT_DIR ?? join(process.env.HOME!, ".pi", "agent");
const CACHE_PATH = join(AGENT_DIR, "cache", "ai-proxy-models.json");

const OWNER_TO_PROVIDER: Record<string, string> = {
  anthropic: "anthropic",
  antigravity: "google",
  google: "google",
  moonshot: "moonshotai",
  moonshotai: "moonshotai",
  openai: "openai",
  xai: "xai",
};

// Proxy-specific variants reuse canonical models.dev metadata and change only
// the property that differs at the proxy boundary.
const MODEL_ALIASES: Record<
  string,
  { provider: string; id: string; overrides?: Partial<Model> }
> = {
  "kimi-k3-256k": {
    provider: "moonshotai",
    id: "kimi-k3",
    overrides: { contextWindow: 256 * 1024 },
  },
};

type ServedModel = { id: string; owner?: string };
type ModelCache = { version: 1; models: Record<string, Model | null> };
type ModelsDevModel = {
  id: string;
  name?: string;
  reasoning?: boolean;
  reasoning_options?: Array<
    { type: "effort"; values?: string[] } | { type: "toggle" }
  >;
  modalities?: { input?: string[] };
  limit?: { context?: number; output?: number };
  cost?: {
    input?: number;
    output?: number;
    cache_read?: number;
    cache_write?: number;
  };
};
type ModelsDevCatalog = Record<
  string,
  { models?: Record<string, ModelsDevModel> }
>;

function emptyCache(): ModelCache {
  return { version: 1, models: {} };
}

async function readCache(): Promise<ModelCache> {
  try {
    const cache = JSON.parse(await readFile(CACHE_PATH, "utf8")) as ModelCache;
    return cache?.version === 1 && cache.models ? cache : emptyCache();
  } catch {
    return emptyCache();
  }
}

async function writeCache(cache: ModelCache): Promise<void> {
  await mkdir(dirname(CACHE_PATH), { recursive: true });
  const temporaryPath = `${CACHE_PATH}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(cache, null, 2)}\n`, "utf8");
  await rename(temporaryPath, CACHE_PATH);
}

function providerCandidates(id: string, owner?: string): string[] {
  const alias = MODEL_ALIASES[id];
  const candidates = [
    alias?.provider,
    owner ? OWNER_TO_PROVIDER[owner] : undefined,
    id.startsWith("claude-") ? "anthropic" : undefined,
    id.startsWith("gemini-") || id.startsWith("gemma-") ? "google" : undefined,
  ];
  return [...new Set(candidates.filter((value): value is string => !!value))];
}

function sourceId(id: string): string {
  return MODEL_ALIASES[id]?.id ?? id;
}

function cacheKeys(id: string, owner?: string): string[] {
  const canonicalId = sourceId(id);
  const candidates = providerCandidates(id, owner);
  return candidates.length > 0
    ? candidates.map((provider) => `${provider}/${canonicalId}`)
    : [`unknown/${canonicalId}`];
}

function hasCachedResolution(
  id: string,
  owner: string | undefined,
  models: Record<string, Model | null>,
): boolean {
  const canonicalId = sourceId(id);
  return (
    cacheKeys(id, owner).some((key) => Object.hasOwn(models, key)) ||
    Object.keys(models).some((key) => key.endsWith(`/${canonicalId}`))
  );
}

function findModel(
  id: string,
  owner: string | undefined,
  models: Record<string, Model | null>,
): Model | undefined {
  const canonicalId = sourceId(id);
  for (const key of cacheKeys(id, owner)) {
    const model = models[key];
    if (model) return model;
  }

  return (
    Object.entries(models).find(
      ([key, model]) => model && key.endsWith(`/${canonicalId}`),
    )?.[1] ?? undefined
  );
}

function thinkingLevelMap(
  options: ModelsDevModel["reasoning_options"],
): Model["thinkingLevelMap"] | undefined {
  if (!options?.length) return undefined;

  const values = new Set(
    options.flatMap((option) =>
      option.type === "effort" ? (option.values ?? []) : [],
    ),
  );
  const hasToggle = options.some((option) => option.type === "toggle");
  const levels = ["minimal", "low", "medium", "high", "xhigh", "max"] as const;
  return {
    off: null,
    ...Object.fromEntries(
      levels.map((level) => [
        level,
        values.has(level)
          ? level
          : hasToggle && level === "high"
            ? "high"
            : null,
      ]),
    ),
  };
}

function normalizeModel(provider: string, model: ModelsDevModel): Model {
  const input = model.modalities?.input ?? ["text"];
  return {
    id: model.id,
    name: model.name ?? model.id,
    provider,
    api: "openai-completions",
    baseUrl: BASE_URL,
    reasoning: model.reasoning ?? false,
    input: input.includes("image") ? ["text", "image"] : ["text"],
    cost: {
      input: model.cost?.input ?? 0,
      output: model.cost?.output ?? 0,
      cacheRead: model.cost?.cache_read ?? 0,
      cacheWrite: model.cost?.cache_write ?? 0,
    },
    contextWindow: model.limit?.context ?? 128_000,
    maxTokens: model.limit?.output ?? 16_384,
    thinkingLevelMap: thinkingLevelMap(model.reasoning_options),
  };
}

function findCatalogModel(
  served: ServedModel,
  catalog: ModelsDevCatalog,
): { provider: string; model: ModelsDevModel } | undefined {
  const id = sourceId(served.id);
  for (const provider of providerCandidates(served.id, served.owner)) {
    const model = catalog[provider]?.models?.[id];
    if (model) return { provider, model };
  }

  for (const [provider, entry] of Object.entries(catalog)) {
    const model = entry.models?.[id];
    if (model) return { provider, model };
  }
  return undefined;
}

async function fetchCatalog(): Promise<ModelsDevCatalog> {
  const response = await fetch(MODELS_DEV_URL, {
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(
      `models.dev catalog fetch failed: ${response.status} ${response.statusText}`,
    );
  }
  return (await response.json()) as ModelsDevCatalog;
}

async function resolveModels(served: ServedModel[]): Promise<Model[]> {
  const cache = await readCache();
  const missing = served.filter(
    ({ id, owner }) => !hasCachedResolution(id, owner, cache.models),
  );

  if (missing.length > 0) {
    const catalog = await fetchCatalog();
    let changed = false;
    for (const model of missing) {
      const match = findCatalogModel(model, catalog);
      if (match) {
        cache.models[`${match.provider}/${match.model.id}`] = normalizeModel(
          match.provider,
          match.model,
        );
      } else {
        cache.models[cacheKeys(model.id, model.owner)[0]] = null;
      }
      changed = true;
    }
    if (changed) await writeCache(cache);
  }

  return served.flatMap(({ id, owner }) => {
    const source = findModel(id, owner, cache.models);
    if (!source) return [];
    const alias = MODEL_ALIASES[id];
    return [
      {
        ...source,
        ...alias?.overrides,
        id,
        provider: "ai-proxy",
        baseUrl: BASE_URL,
        api: "openai-completions" as const,
      },
    ];
  });
}

async function fetchServedModels(apiKey: string): Promise<ServedModel[]> {
  const response = await fetch(`${BASE_URL}/models`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(
      `AI Proxy model discovery failed: ${response.status} ${response.statusText}`,
    );
  }

  const payload = (await response.json()) as {
    data?: Array<{ id?: string; owned_by?: string }>;
  };
  return (payload.data ?? []).flatMap(({ id, owned_by }) =>
    id ? [{ id, owner: owned_by }] : [],
  );
}

export default async function (pi: ExtensionAPI) {
  const apiKey = (await readFile(API_KEY_PATH, "utf8")).trim();
  const served = await fetchServedModels(apiKey);
  const models = await resolveModels(served);

  pi.registerProvider("ai-proxy", {
    name: "AI Proxy",
    baseUrl: BASE_URL,
    apiKey: `!cat ${JSON.stringify(API_KEY_PATH)}`,
    api: "openai-completions",
    models,
  });
}
