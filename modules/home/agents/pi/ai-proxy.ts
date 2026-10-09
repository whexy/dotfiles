import {
  getAgentDir,
  type ExtensionAPI,
  type ProviderModelConfig,
} from "@earendil-works/pi-coding-agent";
import type { Api, Model } from "@earendil-works/pi-ai";
import {
  getBuiltinModels,
  getBuiltinProviders,
} from "@earendil-works/pi-ai/providers/all";
import { execFile } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
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
  fallbackModels: string[];
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
  // Without any cliproxyapi model, pi starts on another provider's model
  // instead, so an outage before the first successful discovery registers
  // the models pi is configured to use.
  fallbackModels: FALLBACK_MODELS,
} = loadConfig();

const BASE_URL = `${PROXY_BASE_URL}/v1`;
const CACHE_PATH = join(getAgentDir(), "cache", "cliproxyapi-model-ids.json");

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
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as { data?: Array<{ id?: string }> };
  return (payload.data ?? []).flatMap(({ id }) => (id ? [id] : []));
}

async function discoverServedIds(): Promise<string[]> {
  const [apiKey, cfAccessId, cfAccessSecret] = await Promise.all([
    readSecret(API_KEY_PATH),
    readSecret(CF_ACCESS_ID_PATH),
    readSecret(CF_ACCESS_SECRET_PATH),
  ]);
  return fetchServedIds(apiKey, {
    "CF-Access-Client-Id": cfAccessId,
    "CF-Access-Client-Secret": cfAccessSecret,
  });
}

async function readCachedIds(): Promise<string[] | undefined> {
  try {
    const ids = JSON.parse(await readFile(CACHE_PATH, "utf8")) as unknown;
    if (Array.isArray(ids) && ids.every((id) => typeof id === "string")) {
      return ids;
    }
  } catch {
    // An absent or unreadable cache is the same as none.
  }
  return undefined;
}

// Concurrent pi processes each rename a complete file into place.
async function writeCachedIds(ids: string[]): Promise<void> {
  await mkdir(dirname(CACHE_PATH), { recursive: true });
  const temporaryPath = `${CACHE_PATH}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(ids)}\n`, "utf8");
  await rename(temporaryPath, CACHE_PATH);
}

export default async function (pi: ExtensionAPI) {
  let ids: string[];
  try {
    ids = await discoverServedIds();
    // A cache that cannot be written only costs the next outage its list.
    await writeCachedIds(ids).catch(() => {});
  } catch (error) {
    // Pi exits when an extension fails to load, so a brief proxy outage
    // must fall back instead of throwing.
    const cached = await readCachedIds();
    ids = cached ?? FALLBACK_MODELS;
    const reason = error instanceof Error ? error.message : String(error);
    const notice =
      `CLIProxyAPI model list unavailable (${reason}); using ` +
      (cached ? "the last list it served" : "the configured default models");
    const unsubscribe = pi.on("session_start", (_event, ctx) => {
      unsubscribe();
      if (ctx.hasUI) ctx.ui.notify(notice, "warning");
    });
  }

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
