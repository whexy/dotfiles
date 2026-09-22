import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { execFile } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const CATALOG_BASE_URL = "https://pi.dev";

// Injected by Home Manager (see proxy.nix). The secret paths are agenix
// shell fragments rather than literal paths, so they are only valid inside
// a shell; `readSecret` is the single place that resolves them.
type AiProxyConfig = {
  baseUrl: string;
  apiKeyPath: string;
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
  baseUrl: PROXY_BASE_URL,
  apiKeyPath: API_KEY_PATH,
  // The proxy is published on the public internet behind Cloudflare Access;
  // without the service token every request stops at the 403 login page.
  cfAccessIdPath: CF_ACCESS_ID_PATH,
  cfAccessSecretPath: CF_ACCESS_SECRET_PATH,
  cat: CAT,
} = loadConfig();

const BASE_URL = `${PROXY_BASE_URL}/v1`;
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

// Proxy-specific variants reuse the canonical catalog entry and change only
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
type ModelCache = { version: 2; models: Record<string, Model> };
type ProviderCatalog = Record<string, Model> | null;

function emptyCache(): ModelCache {
  return { version: 2, models: {} };
}

async function readCache(): Promise<ModelCache> {
  try {
    const cache = JSON.parse(await readFile(CACHE_PATH, "utf8")) as ModelCache;
    if (cache?.version !== 2 || !cache.models) return emptyCache();
    // Older caches contain permanent negative entries; retry those lookups.
    cache.models = Object.fromEntries(
      Object.entries(cache.models).filter(([, model]) => model != null),
    );
    return cache;
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
  models: Record<string, Model>,
): boolean {
  const canonicalId = sourceId(id);
  return (
    cacheKeys(id, owner).some((key) => !!models[key]) ||
    Object.entries(models).some(
      ([key, model]) => !!model && key.endsWith(`/${canonicalId}`),
    )
  );
}

function findModel(
  id: string,
  owner: string | undefined,
  models: Record<string, Model>,
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

// Catalog entries are already pi Models carrying the wire-compat metadata the
// proxy's upstreams need; strip only the fields the registration overrides.
function normalizeModel(source: Model): Model {
  const { provider: _p, baseUrl: _b, api: _a, ...model } = source;
  return model;
}

// The catalog serves one provider per endpoint. A 404/501 means the provider
// has no remote catalog; other failures throw so callers can retry later.
async function fetchProviderCatalog(
  provider: string,
): Promise<ProviderCatalog> {
  const url = new URL(
    `/api/models/providers/${encodeURIComponent(provider)}`,
    CATALOG_BASE_URL,
  );
  const response = await fetch(url, {
    headers: { accept: "application/json" },
    signal: AbortSignal.timeout(10_000),
  });
  if (response.status === 404 || response.status === 501) return null;
  if (!response.ok) {
    throw new Error(
      `Model catalog request failed for ${provider}: ${response.status} ${response.statusText}`,
    );
  }

  const payload = (await response.json()) as unknown;
  const entries: Model[] = Array.isArray(payload)
    ? payload
    : typeof payload === "object" &&
        payload !== null &&
        Array.isArray((payload as { models?: Model[] }).models)
      ? (payload as { models: Model[] }).models
      : typeof payload === "object" && payload !== null
        ? Object.values(payload)
        : [];
  const catalog: Record<string, Model> = {};
  for (const model of entries) {
    if (typeof model?.id === "string") catalog[model.id] = model;
  }
  return catalog;
}

async function resolveModels(served: ServedModel[]): Promise<Model[]> {
  const cache = await readCache();
  const missing = served.filter(
    ({ id, owner }) => !hasCachedResolution(id, owner, cache.models),
  );

  if (missing.length > 0) {
    // One fetch per provider per run, shared across models.
    const catalogs = new Map<string, Promise<ProviderCatalog>>();
    const catalogFor = (provider: string): Promise<ProviderCatalog> => {
      if (!catalogs.has(provider)) {
        catalogs.set(provider, fetchProviderCatalog(provider));
      }
      return catalogs.get(provider)!;
    };

    let changed = false;
    for (const model of missing) {
      const canonicalId = sourceId(model.id);
      const candidates = providerCandidates(model.id, model.owner);
      const outcomes = await Promise.all(
        candidates.map((provider) =>
          catalogFor(provider)
            .then((catalog) => ({ provider, catalog, failed: false }))
            .catch(() => ({ provider, catalog: null, failed: true })),
        ),
      );

      let resolved: { provider: string; model: Model } | undefined;
      for (const { provider, catalog, failed } of outcomes) {
        if (failed) continue;
        const match = catalog?.[canonicalId];
        if (match && !resolved) resolved = { provider, model: match };
      }

      if (resolved) {
        cache.models[`${resolved.provider}/${canonicalId}`] = normalizeModel(
          resolved.model,
        );
        changed = true;
      }
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

async function fetchServedModels(
  apiKey: string,
  cfAccess: Record<string, string>,
): Promise<ServedModel[]> {
  const response = await fetch(`${BASE_URL}/models`, {
    headers: { Authorization: `Bearer ${apiKey}`, ...cfAccess },
    // undici strips Authorization across origins but forwards custom headers,
    // so a redirect would hand the Cloudflare Access token to whatever origin
    // it names. Refuse to follow rather than leak it.
    redirect: "error",
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
  const [apiKey, cfAccessId, cfAccessSecret] = await Promise.all([
    readSecret(API_KEY_PATH),
    readSecret(CF_ACCESS_ID_PATH),
    readSecret(CF_ACCESS_SECRET_PATH),
  ]);
  const served = await fetchServedModels(apiKey, {
    "CF-Access-Client-Id": cfAccessId,
    "CF-Access-Client-Secret": cfAccessSecret,
  });
  const models = await resolveModels(served);

  pi.registerProvider("ai-proxy", {
    name: "AI Proxy",
    baseUrl: BASE_URL,
    // pi runs `!` values through a shell and resolves them per request, so
    // the agenix path expands and a re-decrypted token is picked up without
    // restarting the session. The double quotes are what make it expand.
    apiKey: `!${CAT} "${API_KEY_PATH}"`,
    api: "openai-completions",
    headers: {
      "CF-Access-Client-Id": `!${CAT} "${CF_ACCESS_ID_PATH}"`,
      "CF-Access-Client-Secret": `!${CAT} "${CF_ACCESS_SECRET_PATH}"`,
    },
    models,
  });
}
