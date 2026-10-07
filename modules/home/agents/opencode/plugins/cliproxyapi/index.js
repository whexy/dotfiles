// OpenCode plugin: the CLIProxyAPI provider, with the proxy's live model list.
//
// Every model /v1/models serves is registered and refreshed while OpenCode
// runs, so models the proxy drops disappear without a restart. A model takes
// its package (wire format), limits, and capabilities from the entry with the
// same ID in OpenCode's own catalog, vendors first. Models the catalog does
// not know use the OpenAI-compatible package with OpenCode's model defaults.
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

async function fetchServed(baseUrl, credentials) {
  const response = await fetch(`${baseUrl}/v1/models`, {
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
  if (!Array.isArray(payload?.data)) {
    throw new Error("CLIProxyAPI model discovery returned no model list");
  }
  const ids = payload.data
    .map((model) => model?.id)
    .filter((id) => typeof id === "string" && id.length > 0);
  return [...new Set(ids)].sort();
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

function proxyModel(editor, baseUrl, id) {
  const match = catalogEntry(editor, id);
  const pkg = match?.pkg ?? FALLBACK;
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
  return {
    ...model,
    id,
    modelID: id,
    providerID: PROVIDER,
    package: pkg,
    settings: { ...settings, baseURL: `${baseUrl}${PATHS[pkg]}` },
  };
}

export default {
  id: "dotfiles.cliproxyapi",
  setup: async (ctx) => {
    const options = ctx.options;
    const baseUrl = options.baseUrl.replace(/\/+$/, "");
    const state = { credentials: undefined, ids: [] };

    const refresh = async () => {
      const credentials = await readCredentials(options);
      const ids = await fetchServed(baseUrl, credentials);
      const changed =
        JSON.stringify(ids) !== JSON.stringify(state.ids) ||
        JSON.stringify(credentials) !== JSON.stringify(state.credentials);
      state.credentials = credentials;
      state.ids = ids;
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
          },
          headers: state.credentials.headers,
        },
        models: state.ids.map((id) => proxyModel(editor, baseUrl, id)),
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
