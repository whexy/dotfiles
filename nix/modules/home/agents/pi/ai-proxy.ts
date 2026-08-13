import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getModels, getProviders } from "@earendil-works/pi-ai/compat";
import type { Model } from "@earendil-works/pi-ai";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const baseUrl = "https://ai-proxy.at-basking.ts.net/v1";
const keyPath = join(process.env.HOME!, ".secrets", "ai-proxy-api-key");

const preferredProviders = [
  "openai",
  "anthropic",
  "google",
  "xai",
  "moonshotai",
] as const;
const providers = [
  ...preferredProviders,
  ...getProviders().filter(
    (provider) =>
      !preferredProviders.includes(
        provider as (typeof preferredProviders)[number],
      ),
  ),
];

const modelsByProvider = new Map(
  providers.map((provider) => [provider, getModels(provider)]),
);
const modelsById = new Map<string, Model>();
for (const provider of providers) {
  for (const model of modelsByProvider.get(provider) ?? []) {
    if (!modelsById.has(model.id)) modelsById.set(model.id, model);
  }
}

const ownerProviders: Record<string, string> = {
  openai: "openai",
  xai: "xai",
  moonshot: "moonshotai",
};

function findBundledModel(id: string, owner?: string): Model | undefined {
  const ownerProvider = owner ? ownerProviders[owner] : undefined;
  const prefixProvider = id.startsWith("claude-")
    ? "anthropic"
    : id.startsWith("gemini-")
      ? "google"
      : undefined;

  for (const provider of [ownerProvider, prefixProvider]) {
    const model = provider
      ? modelsByProvider.get(provider)?.find((candidate) => candidate.id === id)
      : undefined;
    if (model) return model;
  }

  return modelsById.get(id);
}

export default async function (pi: ExtensionAPI) {
  const apiKey = (await readFile(keyPath, "utf8")).trim();
  const response = await fetch(`${baseUrl}/models`, {
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
  const models = (payload.data ?? []).flatMap(({ id, owned_by: owner }) => {
    if (!id) return [];
    const source = findBundledModel(id, owner);
    if (!source) return [];

    const { provider: _provider, baseUrl: _baseUrl, ...model } = source;
    return [{ ...model, api: "openai-completions" as const }];
  });

  pi.registerProvider("ai-proxy", {
    name: "AI Proxy",
    baseUrl,
    apiKey: `!cat ${JSON.stringify(keyPath)}`,
    api: "openai-completions",
    models,
  });
}
