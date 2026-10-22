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
//
// OpenCode decodes and replays provider-hosted web search but never declares
// the tool, so it is added on the wire when the model's proxy route
// (`owned_by` in the OpenAI-shaped list) hands it to a provider that runs it.
// Every other model gets OpenCode's own `websearch` tool, backed by the
// cluster's SearXNG behind the proxy's Cloudflare Access service token.
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const PROVIDER = "cliproxyapi";
const REFRESH_MS = 60_000;
// Gateways list the same model ID under their own package, so the model's
// vendor is consulted before them.
const VENDORS = ["anthropic", "openai", "google", "xai", "meta"];
// CLIProxyAPI accepts each package's wire format for every model it serves.
// Each value is the API path in the convention that package appends to.
const PATHS = {
  "@opencode/ai/providers/openai": "/v1",
  "@opencode/ai/providers/openai/responses": "/v1",
  "@opencode/ai/providers/anthropic": "/v1",
  "@opencode/ai/providers/xai": "/v1",
  "@opencode/ai/providers/meta/responses": "/v1",
  "@opencode/ai/providers/google": "/v1beta",
  "@opencode/ai/providers/openai-compatible": "/v1",
};
const FALLBACK = "@opencode/ai/providers/openai-compatible";
// Routes whose executor passes a hosted search tool to a provider that runs
// it. Antigravity drops the tool, and Chat Completions upstreams turn a
// Messages search tool into a client function OpenCode cannot run.
const SEARCH_ROUTES = new Set(["openai", "anthropic", "xai", "meta"]);
// Codex's live mode; its cached mode (`false`) searches only OpenAI's index.
const RESPONSES_SEARCH = { type: "web_search", external_web_access: true };
const MESSAGES_SEARCH = { type: "web_search_20250305", name: "web_search" };
// SearXNG answers with a page of about 20; OpenCode's own backends return 8.
const SEARXNG_RESULTS = 8;

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

async function fetchModels(baseUrl, credentials, query = "") {
  const response = await fetch(`${baseUrl}/v1/models${query}`, {
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
  return response.json();
}

async function fetchOwners(baseUrl, credentials) {
  const payload = await fetchModels(baseUrl, credentials);
  if (!Array.isArray(payload?.data)) {
    throw new Error("CLIProxyAPI model discovery returned no model owners");
  }
  return new Map(
    payload.data.flatMap((record) =>
      typeof record?.id === "string" && typeof record.owned_by === "string"
        ? [[record.id, record.owned_by]]
        : [],
    ),
  );
}

async function fetchServed(baseUrl, credentials, codexVersion) {
  const query = new URLSearchParams({ client_version: codexVersion });
  const payload = await fetchModels(baseUrl, credentials, `?${query}`);
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

function proxyModel(editor, baseUrl, served) {
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

async function searxng(searchUrl, headers, query, signal) {
  const url = new URL("/search", searchUrl);
  url.search = new URLSearchParams({ q: query, format: "json" }).toString();
  const response = await fetch(url, {
    headers,
    // A redirect would hand the Cloudflare Access token to another origin.
    redirect: "error",
    signal: AbortSignal.any([signal, AbortSignal.timeout(25_000)]),
  });
  if (!response.ok) {
    throw new Error(`SearXNG search failed: ${response.status}`);
  }
  const payload = await response.json();
  if (!Array.isArray(payload?.results)) {
    throw new Error("SearXNG returned no result list");
  }
  return payload.results
    .filter((result) => typeof result?.url === "string")
    .slice(0, SEARXNG_RESULTS)
    .map((result) => {
      const published = Date.parse(result.publishedDate);
      return {
        url: result.url,
        ...(typeof result.title === "string" && result.title
          ? { title: result.title }
          : {}),
        ...(typeof result.content === "string" && result.content
          ? { content: result.content }
          : {}),
        // OpenCode rejects a result without `time`, even an empty one.
        time: Number.isFinite(published) ? { published } : {},
      };
    });
}

// A request without tools is one the agent made toolless on purpose.
function addSearch(body, tool) {
  if (!Array.isArray(body?.tools) || body.tools.length === 0) return false;
  if (body.tools.some((t) => String(t?.type).startsWith("web_search")))
    return false;
  body.tools.push(tool);
  return true;
}

export default {
  id: "dotfiles.cliproxyapi",
  setup: async (ctx) => {
    const options = ctx.options;
    const baseUrl = options.baseUrl.replace(/\/+$/, "");
    const state = { credentials: undefined, served: [], owners: new Map() };

    const refresh = async () => {
      const credentials = await readCredentials(options);
      const [served, owners] = await Promise.all([
        fetchServed(baseUrl, credentials, options.codexVersion),
        fetchOwners(baseUrl, credentials),
      ]);
      const changed =
        JSON.stringify(served) !== JSON.stringify(state.served) ||
        JSON.stringify(credentials) !== JSON.stringify(state.credentials);
      state.credentials = credentials;
      state.served = served;
      // Owners only gate search per request, so they need no provider reload.
      state.owners = owners;
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

    await ctx.websearch.transform((editor) => {
      editor.add({
        id: "searxng",
        name: "SearXNG",
        execute: async ({ query }, { signal }) => {
          if (!state.credentials) {
            throw new Error("cliproxyapi: Cloudflare Access token not loaded");
          }
          return searxng(
            options.searchUrl,
            state.credentials.headers,
            query,
            signal,
          );
        },
      });
    });

    const hosted = (model) => SEARCH_ROUTES.has(state.owners.get(model.id));
    // A model with hosted search keeps only that one.
    for (const name of ["context", "compaction"]) {
      await ctx.session.hook(
        name,
        (event) => {
          if (hosted(event.model)) delete event.tools.websearch;
        },
        { providerID: PROVIDER },
      );
    }
    // Compaction keeps the agent turn's tools to reuse its prompt cache;
    // titles carry none.
    const searches = (event) =>
      (event.kind === "primary" || event.kind === "compaction") &&
      hosted(event.model);
    await ctx.session.hook(
      "experimental.ws.send",
      (event) => {
        if (!searches(event)) return;
        const frame = JSON.parse(event.frame);
        if (
          frame.type === "response.create" &&
          addSearch(frame, RESPONSES_SEARCH)
        )
          event.frame = JSON.stringify(frame);
      },
      { providerID: PROVIDER },
    );
    await ctx.session.hook(
      "http.request",
      async (event) => {
        if (!searches(event) || event.request.method !== "POST") return;
        const path = new URL(event.request.url).pathname;
        const tool = path.endsWith("/responses")
          ? RESPONSES_SEARCH
          : path.endsWith("/messages")
            ? MESSAGES_SEARCH
            : undefined;
        if (!tool) return;
        const body = await event.request.clone().json();
        if (!addSearch(body, tool)) return;
        const headers = new Headers(event.request.headers);
        headers.delete("content-length");
        event.request = new Request(event.request, {
          headers,
          body: JSON.stringify(body),
        });
      },
      { providerID: PROVIDER },
    );

    const timer = setInterval(() => {
      refresh()
        .then((changed) => changed && ctx.provider.reload())
        .catch((error) => console.error(error));
    }, REFRESH_MS);
    return () => clearInterval(timer);
  },
};
