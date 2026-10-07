import type {
  ExtensionAPI,
  ProviderModelConfig,
} from "@earendil-works/pi-coding-agent";
import type { Api, Model } from "@earendil-works/pi-ai";
import {
  getBuiltinModels,
  getBuiltinProviders,
} from "@earendil-works/pi-ai/providers/all";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

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
      "cliproxyapi: __AI_PROXY_CONFIG__ is unset; load the extension built by " +
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

// CLIProxyAPI accepts every one of these formats for every model it serves,
// so a catalog entry only decides which one fits the model best. Each value is
// the base URL in the convention pi's client for that API expects.
const PROXY_URLS: Partial<Record<Api, string>> = {
  "openai-responses": BASE_URL,
  "openai-completions": BASE_URL,
  "anthropic-messages": PROXY_BASE_URL,
  "google-generative-ai": `${PROXY_BASE_URL}/v1beta`,
};

// Gateways in pi's catalog list the same model ID under their own API, so
// the model's vendor is consulted before them.
const VENDORS = ["anthropic", "openai", "google", "xai", "moonshotai"];

function catalogEntry(id: string): Model<Api> | undefined {
  const others = getBuiltinProviders().filter((p) => !VENDORS.includes(p));
  for (const provider of [...VENDORS, ...others]) {
    const model = getBuiltinModels(provider as never).find(
      (entry) => entry.id === id && entry.api in PROXY_URLS,
    );
    if (model) return model;
  }
}

// Models pi's catalog does not know use Chat Completions with the defaults pi
// applies to custom models in models.json. Extension-registered models get no
// such defaults, so they are spelled out here.
function toProxyModel(id: string): ProviderModelConfig {
  const entry = catalogEntry(id);
  if (!entry) {
    return {
      id,
      name: id,
      api: "openai-completions",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 16384,
    };
  }
  const { provider: _p, ...model } = entry;
  return { ...model, baseUrl: PROXY_URLS[entry.api] };
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
    throw new Error(`cliproxyapi: secret is empty or unreadable: ${path}`);
  }
  return secret;
}

async function fetchServedIds(
  apiKey: string,
  cfAccess: Record<string, string>,
): Promise<string[]> {
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
      `CLIProxyAPI model discovery failed: ${response.status} ${response.statusText}`,
    );
  }

  const payload = (await response.json()) as { data?: Array<{ id?: string }> };
  return (payload.data ?? []).flatMap(({ id }) => (id ? [id] : []));
}

export default async function (pi: ExtensionAPI) {
  const [apiKey, cfAccessId, cfAccessSecret] = await Promise.all([
    readSecret(API_KEY_PATH),
    readSecret(CF_ACCESS_ID_PATH),
    readSecret(CF_ACCESS_SECRET_PATH),
  ]);
  const ids = await fetchServedIds(apiKey, {
    "CF-Access-Client-Id": cfAccessId,
    "CF-Access-Client-Secret": cfAccessSecret,
  });

  pi.registerProvider("cliproxyapi", {
    name: "CLIProxyAPI",
    baseUrl: BASE_URL,
    // pi runs `!` values through a shell and resolves them per request, so
    // the agenix path expands and a re-decrypted token is picked up without
    // restarting the session. The double quotes are what make it expand.
    apiKey: `!${CAT} "${API_KEY_PATH}"`,
    headers: {
      "CF-Access-Client-Id": `!${CAT} "${CF_ACCESS_ID_PATH}"`,
      "CF-Access-Client-Secret": `!${CAT} "${CF_ACCESS_SECRET_PATH}"`,
    },
    models: ids.map(toProxyModel),
  });
}
