// OpenCode plugin: fill in metadata for the AI proxy's models.
//
// ai-proxy is a custom provider, so OpenCode knows nothing about its models
// beyond what config declares, and an undeclared context limit disables
// auto-compaction. The proxy serves the upstream labs' models under their
// canonical ids, so their models.dev entries describe them exactly.
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
    const models = config.provider?.[PROVIDER]?.models;
    if (!models) return;

    const providers = await catalog();
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
