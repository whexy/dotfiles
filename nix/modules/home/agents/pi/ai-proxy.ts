import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getModels, getProviders } from "@earendil-works/pi-ai/compat";
import type { Model } from "@earendil-works/pi-ai";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const BASE_URL = "https://ai-proxy.at-basking.ts.net/v1";
const API_KEY_PATH = join(process.env.HOME!, ".secrets", "ai-proxy-api-key");

// Providers checked first when resolving a model id.
const PREFERRED_PROVIDERS = [
  "openai",
  "anthropic",
  "google",
  "xai",
  "moonshotai",
] as const;

// Maps the proxy's `owned_by` tags to pi-ai provider names.
const OWNER_TO_PROVIDER: Record<string, string> = {
  openai: "openai",
  xai: "xai",
  moonshot: "moonshotai",
};

// Aliases for models the proxy serves that don't exist in pi-ai's registry.
// Each alias clones a bundled model, optionally overriding some fields.
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

type ModelIndex = {
  byProvider: Map<string, Model[]>;
  byId: Map<string, Model>;
};

function buildModelIndex(): ModelIndex {
  const providerNames = [
    ...PREFERRED_PROVIDERS,
    ...getProviders().filter(
      (provider) =>
        !PREFERRED_PROVIDERS.includes(
          provider as (typeof PREFERRED_PROVIDERS)[number],
        ),
    ),
  ];

  const byProvider = new Map(
    providerNames.map((provider) => [provider, getModels(provider)]),
  );
  const byId = new Map<string, Model>();
  for (const provider of providerNames) {
    for (const model of byProvider.get(provider) ?? []) {
      if (!byId.has(model.id)) byId.set(model.id, model);
    }
  }
  return { byProvider, byId };
}

// Finds the bundled model matching a proxy-served id, preferring the
// owner's provider, then well-known id prefixes, then a global lookup.
function findBundledModel(
  id: string,
  owner: string | undefined,
  index: ModelIndex,
): Model | undefined {
  const candidateProviders = [
    owner ? OWNER_TO_PROVIDER[owner] : undefined,
    id.startsWith("claude-") ? "anthropic" : undefined,
    id.startsWith("gemini-") ? "google" : undefined,
  ];

  for (const provider of candidateProviders) {
    const model = provider
      ? index.byProvider.get(provider)?.find((m) => m.id === id)
      : undefined;
    if (model) return model;
  }

  return index.byId.get(id);
}

// Converts a proxy model entry into a pi model registration, cloning
// metadata from the bundled registry. Returns undefined for unknown models.
function resolveModel(
  id: string,
  owner: string | undefined,
  index: ModelIndex,
) {
  const alias = MODEL_ALIASES[id];
  const source = alias
    ? index.byProvider.get(alias.provider)?.find((m) => m.id === alias.id)
    : findBundledModel(id, owner, index);
  if (!source) return undefined;

  const { provider: _provider, baseUrl: _baseUrl, ...model } = source;
  return {
    ...model,
    ...alias?.overrides,
    id,
    api: "openai-completions" as const,
  };
}

async function fetchServedModels(
  apiKey: string,
): Promise<Array<{ id: string; owner?: string }>> {
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
  const index = buildModelIndex();
  const served = await fetchServedModels(apiKey);
  const models = served.flatMap(({ id, owner }) => {
    const model = resolveModel(id, owner, index);
    return model ? [model] : [];
  });

  pi.registerProvider("ai-proxy", {
    name: "AI Proxy",
    baseUrl: BASE_URL,
    apiKey: `!cat ${JSON.stringify(API_KEY_PATH)}`,
    api: "openai-completions",
    models,
  });
}
