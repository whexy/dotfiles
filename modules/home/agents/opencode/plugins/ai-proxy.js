// OpenCode plugin: discover CLIProxyAPI's models and enrich their metadata.
//
// cliproxyapi is a custom provider, so OpenCode knows nothing about its models
// beyond what config declares. Discovery must register even models absent from
// models.dev so experimental proxy IDs can be tried without editing dotfiles.
// Known IDs inherit metadata, including auto-compaction limits, and the SDK
// models.dev assigns them; unknown IDs keep the provider's OpenAI-compatible
// default.
//
// OpenCode keeps its own models.dev snapshot in its cache directory; read that
// and fall back to fetching only when it has not been written yet.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const PROVIDER = "cliproxyapi";
const SOURCE = "https://models.opencode.ai/api.json";
// Gateways in models.dev list the same model ID under their own SDK, so the
// model's vendor is consulted before them.
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
// models.dev SDK -> the SDK and API path used against CLIProxyAPI, which
// accepts each of these wire formats for every model it serves. The path
// follows the convention that SDK appends to.
//
// OpenCode's built-in xai provider streams through `sdk.responses()`, a
// loader config-defined providers cannot select; the xai SDK's default chat
// model rejects OpenAI-style incremental tool-call chunks. The openai SDK
// reaches the same Responses API.
const SDKS = {
  "@ai-sdk/openai": { npm: "@ai-sdk/openai", path: "/v1" },
  "@ai-sdk/openai-compatible": {
    npm: "@ai-sdk/openai-compatible",
    path: "/v1",
  },
  "@ai-sdk/anthropic": { npm: "@ai-sdk/anthropic", path: "/v1" },
  "@ai-sdk/xai": { npm: "@ai-sdk/openai", path: "/v1" },
  "@ai-sdk/google": { npm: "@ai-sdk/google", path: "/v1beta" },
};

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
    if (!model) continue;
    const npm = model.provider?.npm ?? providers[provider].npm;
    if (Object.hasOwn(SDKS, npm)) return { model, sdk: SDKS[npm] };
  }
}

export const AiProxyPlugin = async () => ({
  config: async (config) => {
    const provider = config.provider?.[PROVIDER];
    if (!provider) return;

    const { apiKey, headers } = provider.options;
    const proxyUrl = new URL(provider.api).origin;
    const response = await fetch(`${provider.api}/models`, {
      headers: { Authorization: `Bearer ${apiKey}`, ...headers },
      // Cloudflare Access headers must not follow redirects to another origin.
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      throw new Error(`CLIProxyAPI model discovery failed: ${response.status}`);
    }
    const payload = await response.json();
    if (
      !Array.isArray(payload?.data) ||
      !payload.data.every(
        (model) => typeof model?.id === "string" && model.id.length > 0,
      )
    ) {
      throw new Error(
        "CLIProxyAPI model discovery returned an invalid model list",
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
      const match = lookup(providers, model.id ?? id);
      if (!match) continue;
      for (const field of FIELDS) {
        if (model[field] === undefined && match.model[field] !== undefined) {
          model[field] = match.model[field];
        }
      }
      model.provider ??= {
        npm: match.sdk.npm,
        api: `${proxyUrl}${match.sdk.path}`,
      };
    }
  },
});
