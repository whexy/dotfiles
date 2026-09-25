// OpenCode plugin: discover the AI proxy's models and enrich their metadata.
//
// ai-proxy is a custom provider, so OpenCode knows nothing about its models
// beyond what config declares. Discovery must register even models absent from
// models.dev so experimental proxy IDs can be tried without editing dotfiles.
// Known canonical IDs inherit metadata, including auto-compaction limits.
//
// OpenCode keeps its own models.dev snapshot in its cache directory; read that
// and fall back to fetching only when it has not been written yet.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const PROVIDER = "ai-proxy";
const SOURCE = "https://models.opencode.ai/api.json";
const PREFERRED = ["anthropic", "openai", "google", "xai"];
const FIELDS = [
  "name",
  "family",
  "release_date",
  "attachment",
  "reasoning",
  "temperature",
  "tool_call",
  "limit",
  "modalities",
];

async function catalog() {
  const cache = process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache");
  try {
    return JSON.parse(
      await readFile(join(cache, "opencode", "models.json"), "utf8"),
    );
  } catch {
    const response = await fetch(SOURCE, {
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`${SOURCE}: ${response.status}`);
    return response.json();
  }
}

function lookup(providers, id) {
  const order = [
    ...PREFERRED,
    ...Object.keys(providers).filter((p) => !PREFERRED.includes(p)),
  ];
  for (const provider of order) {
    const model = providers[provider]?.models?.[id];
    if (model) return model;
  }
}

export const AiProxyPlugin = async () => ({
  config: async (config) => {
    const provider = config.provider?.[PROVIDER];
    if (!provider) return;

    const { baseURL, apiKey, headers } = provider.options;
    const response = await fetch(`${baseURL.replace(/\/$/, "")}/models`, {
      headers: { Authorization: `Bearer ${apiKey}`, ...headers },
      // Cloudflare Access headers must not follow redirects to another origin.
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      throw new Error(`AI Proxy model discovery failed: ${response.status}`);
    }
    const payload = await response.json();
    if (
      !Array.isArray(payload?.data) ||
      !payload.data.every(
        (model) => typeof model?.id === "string" && model.id.length > 0,
      )
    ) {
      throw new Error(
        "AI Proxy model discovery returned an invalid model list",
      );
    }
    const models = (provider.models ??= {});
    for (const { id } of payload.data) {
      if (!Object.hasOwn(models, id)) {
        Object.defineProperty(models, id, {
          value: {},
          enumerable: true,
          configurable: true,
          writable: true,
        });
      }
    }

    // Metadata availability must not gate access to the proxy's live models.
    const providers = await catalog().catch(() => ({}));
    for (const [id, model] of Object.entries(models)) {
      const source = lookup(providers, model.id ?? id);
      if (!source) continue;
      for (const field of FIELDS) {
        if (model[field] === undefined && source[field] !== undefined) {
          model[field] = source[field];
        }
      }
    }
  },
});
