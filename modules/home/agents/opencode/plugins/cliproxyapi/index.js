// OpenCode plugin: the CLIProxyAPI provider, with the proxy's live model list.
//
// The model list comes from the proxy's Codex model catalog
// (`/v1/models?client_version=<Codex version>`), whose records carry the
// display names and limits the OpenAI-shaped list omits. Every listed model
// is registered and refreshed while OpenCode runs, so models the proxy drops
// disappear without a restart. A model takes its package (wire format) from
// the entry with the same ID in OpenCode's own catalog, vendors first; its
// name, limits, input modalities, reasoning efforts, and effort-update
// support come from the proxy's catalog, because requests must follow what
// the proxy declares it supports. Models
// neither catalog knows use OpenCode's model defaults. GPT IDs always use
// Responses over WebSocket; other unknown IDs use the OpenAI-compatible HTTP
// package.
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const PROVIDER = "cliproxyapi";
const REFRESH_MS = 60_000;
// Gateways list the same model ID under their own package, so the model's
// vendor is consulted before them.
const VENDORS = ["anthropic", "openai", "google", "xai"];
// CLIProxyAPI accepts each package's wire format for every model it serves.
// Each value is the API path in the convention that package appends to.
const PATHS = {
  "@opencode/ai/providers/openai": "/v1",
  "@opencode/ai/providers/openai/responses": "/v1",
  "@opencode/ai/providers/anthropic": "/v1",
  "@opencode/ai/providers/xai": "/v1",
  "@opencode/ai/providers/google": "/v1beta",
  "@opencode/ai/providers/openai-compatible": "/v1",
};
const FALLBACK = "@opencode/ai/providers/openai-compatible";

const execFileAsync = promisify(execFile);

// Agenix paths are shell fragments (`${XDG_RUNTIME_DIR}/...` on Linux,
// `$(getconf ...)/...` on Darwin), so only a shell can resolve them.
async function readSecret(cat, path) {
  const { stdout } = await execFileAsync("/bin/sh", ["-c", `${cat} "${path}"`]);
  const secret = stdout.trim();
  if (!secret) throw new Error(`cliproxyapi: secret is empty: ${path}`);
  return secret;
}

async function readCredentials(options) {
  const [apiKey, id, secret] = await Promise.all([
    readSecret(options.cat, options.apiKeyPath),
    readSecret(options.cat, options.cfAccessIdPath),
    readSecret(options.cat, options.cfAccessSecretPath),
  ]);
  return {
    apiKey,
    headers: { "CF-Access-Client-Id": id, "CF-Access-Client-Secret": secret },
  };
}

async function fetchServed(baseUrl, credentials, codexVersion) {
  const query = new URLSearchParams({ client_version: codexVersion });
  const response = await fetch(`${baseUrl}/v1/models?${query}`, {
    headers: {
      Authorization: `Bearer ${credentials.apiKey}`,
      ...credentials.headers,
    },
    // A redirect would hand the Cloudflare Access token to another origin.
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`CLIProxyAPI model discovery failed: ${response.status}`);
  }
  const payload = await response.json();
  if (!Array.isArray(payload?.models)) {
    throw new Error("CLIProxyAPI model discovery returned no model list");
  }
  const seen = new Set();
  const served = [];
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
          (modality) => modality === "text" || modality === "image",
        )
      : undefined;
    const efforts = Array.isArray(record.supported_reasoning_levels)
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
      context:
        typeof record.context_window === "number"
          ? record.context_window
          : undefined,
      output:
        typeof record.max_tokens === "number" ? record.max_tokens : undefined,
      input: input && input.length > 0 ? input : undefined,
      efforts,
      defaultEffort:
        typeof record.default_reasoning_level === "string" &&
        record.default_reasoning_level
          ? record.default_reasoning_level
          : undefined,
      effortUpdates:
        typeof record.supports_reasoning_effort_updates === "boolean"
          ? record.supports_reasoning_effort_updates
          : undefined,
    });
  }
  return served.sort((a, b) => a.id.localeCompare(b.id));
}

function catalogEntry(editor, id) {
  const records = editor.list().filter((r) => r.provider.id !== PROVIDER);
  const rank = (r) => {
    const index = VENDORS.indexOf(r.provider.id);
    return index < 0 ? VENDORS.length : index;
  };
  for (const record of records.toSorted((a, b) => rank(a) - rank(b))) {
    const model = record.models.get(id);
    const pkg = model?.package ?? record.provider.package;
    if (model && Object.hasOwn(PATHS, pkg)) return { model, pkg };
  }
}

function deepClone(value) {
  return structuredClone(value);
}

function effortVariant(entry, pkg, effort) {
  const provided = entry?.variants?.find((variant) => variant.id === effort);
  if (provided) return deepClone(provided);
  switch (pkg) {
    case "@opencode/ai/providers/anthropic":
      return {
        id: effort,
        settings: {
          thinking: { type: "adaptive", display: "summarized" },
          effort,
        },
      };
    case "@opencode/ai/providers/google":
      return {
        id: effort,
        settings: {
          thinkingConfig: { thinkingLevel: effort, includeThoughts: true },
        },
      };
    case "@opencode/ai/providers/openai":
    case "@opencode/ai/providers/openai/responses":
    case "@opencode/ai/providers/xai":
      return {
        id: effort,
        settings: {
          reasoningEffort: effort,
          reasoningSummary: "auto",
          include: ["reasoning.encrypted_content"],
        },
      };
    default:
      return { id: effort, settings: { reasoningEffort: effort } };
  }
}

export function proxyModel(editor, baseUrl, served) {
  const id = served.id;
  const match = catalogEntry(editor, id);
  const chatgpt = id.startsWith("gpt-");
  const pkg = chatgpt
    ? "@opencode/ai/providers/openai/responses"
    : (match?.pkg ?? FALLBACK);
  const {
    baseURL: _url,
    provider: _provider,
    ...settings
  } = match?.model.settings ?? {};
  const base = match?.model ?? {
    name: id,
    capabilities: { tools: true, input: ["text", "image"], output: ["text"] },
    variants: [],
    time: { released: 0 },
    cost: [],
    status: "active",
    enabled: true,
    limit: { context: 200_000, output: 32_000 },
  };
  // The catalog entry's provider identity would route usage and options to
  // that vendor instead of this provider.
  const { canonical: _canonical, ...model } = base;
  const modelEfforts = Array.isArray(served.efforts)
    ? served.efforts
    : undefined;
  const variants = modelEfforts
    ? modelEfforts.map((effort) => effortVariant(model, pkg, effort))
    : (model.variants ?? []);
  const defaultSettings = {};
  if (
    modelEfforts &&
    modelEfforts.length > 0 &&
    typeof served.defaultEffort === "string" &&
    !modelEfforts.includes(served.defaultEffort)
  ) {
    console.warn(
      `cliproxyapi: default reasoning effort ${served.defaultEffort} for ${id} is not in CPA's effort list`,
    );
  }
  if (
    modelEfforts &&
    typeof served.defaultEffort === "string" &&
    modelEfforts.includes(served.defaultEffort)
  ) {
    Object.assign(
      defaultSettings,
      effortVariant(model, pkg, served.defaultEffort).settings,
    );
  }
  return {
    ...deepClone(model),
    id,
    modelID: id,
    providerID: PROVIDER,
    package: pkg,
    // The proxy, not OpenCode's catalog, names what it serves: proxy-only
    // models have no catalog entry, and gateways may relabel known ones.
    name: served.name,
    capabilities: {
      ...(model.capabilities ?? {
        tools: true,
        input: ["text", "image"],
        output: ["text"],
      }),
      input: served.input ?? model.capabilities?.input ?? ["text", "image"],
    },
    compatibility: {
      ...(model.compatibility ?? {}),
      ...(typeof served.effortUpdates === "boolean"
        ? { supportsEffortUpdates: served.effortUpdates }
        : {}),
    },
    variants,
    limit: {
      context: served.context ?? model.limit.context,
      output: served.output ?? model.limit.output,
    },
    settings: {
      ...settings,
      ...defaultSettings,
      baseURL: `${baseUrl}${PATHS[pkg]}`,
    },
  };
}

export default {
  id: "dotfiles.cliproxyapi",
  setup: async (ctx) => {
    const options = ctx.options;
    const baseUrl = options.baseUrl.replace(/\/+$/, "");
    const state = { credentials: undefined, served: [] };

    const refresh = async () => {
      const credentials = await readCredentials(options);
      const served = await fetchServed(
        baseUrl,
        credentials,
        options.codexVersion,
      );
      const changed =
        JSON.stringify(served) !== JSON.stringify(state.served) ||
        JSON.stringify(credentials) !== JSON.stringify(state.credentials);
      state.credentials = credentials;
      state.served = served;
      return changed;
    };

    // Keep the last successful list through transient outages.
    await refresh().catch((error) => console.error(error));

    await ctx.provider.transform((editor) => {
      if (!state.credentials) return;
      editor.remove(PROVIDER);
      editor.add({
        info: {
          id: PROVIDER,
          name: "CLIProxyAPI",
          activation: "enabled",
          package: FALLBACK,
          settings: {
            baseURL: `${baseUrl}/v1`,
            apiKey: state.credentials.apiKey,
            // OpenCode selects session transport from the provider, not the
            // model. Only WebSocket-capable Responses adapters consume it;
            // Messages and Chat Completions adapters keep using HTTP.
            transport: "websocket",
          },
          headers: state.credentials.headers,
        },
        models: state.served.map((served) =>
          proxyModel(editor, baseUrl, served),
        ),
      });
    });

    const timer = setInterval(() => {
      refresh()
        .then((changed) => changed && ctx.provider.reload())
        .catch((error) => console.error(error));
    }, REFRESH_MS);
    return () => clearInterval(timer);
  },
};
