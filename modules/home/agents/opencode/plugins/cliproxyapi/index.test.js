import { expect, test } from "bun:test";
import plugin, { proxyModel } from "./index.js";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

const editor = {
  list: () => [
    {
      provider: { id: "openai", package: "@opencode/ai/providers/openai" },
      models: new Map([
        [
          "gpt-test",
          {
            name: "GPT",
            limit: { context: 100, output: 10 },
            capabilities: {
              tools: true,
              input: ["text", "image", "pdf"],
              output: ["text"],
            },
            compatibility: { supportsPromptCacheKey: true },
            variants: [
              { id: "low", settings: { reasoningEffort: "low" } },
              { id: "max", settings: { reasoningEffort: "max" } },
            ],
            settings: {
              baseURL: "https://api.openai.com/v1",
              transport: "http",
            },
          },
        ],
      ]),
    },
    {
      provider: {
        id: "anthropic",
        package: "@opencode/ai/providers/anthropic",
      },
      models: new Map([
        [
          "claude-test",
          {
            name: "Claude",
            limit: { context: 200, output: 20 },
            capabilities: {
              tools: true,
              input: ["text", "image", "pdf"],
              output: ["text"],
            },
            variants: [{ id: "max", settings: { effort: "max" } }],
            settings: {},
          },
        ],
      ]),
    },
    {
      provider: {
        id: "google",
        package: "@opencode/ai/providers/google",
      },
      models: new Map([
        [
          "gemini-test",
          {
            name: "Gemini",
            limit: { context: 200, output: 20 },
            capabilities: {
              tools: true,
              input: ["text", "image", "audio"],
              output: ["text"],
            },
            variants: [],
            settings: {},
          },
        ],
      ]),
    },
    {
      provider: {
        id: "xai",
        package: "@opencode/ai/providers/xai",
      },
      models: new Map([
        [
          "grok-test",
          {
            name: "Grok",
            limit: { context: 200, output: 20 },
            capabilities: {
              tools: true,
              input: ["text", "image"],
              output: ["text"],
            },
            variants: [],
            settings: {},
          },
        ],
      ]),
    },
  ],
};

test("GPT models explicitly use Responses WebSocket, including new catalog IDs", () => {
  for (const id of ["gpt-test", "gpt-unknown"]) {
    const model = proxyModel(editor, "https://proxy.test", { id, name: id });
    expect(model.package).toBe("@opencode/ai/providers/openai/responses");
    expect(model.settings.baseURL).toBe("https://proxy.test/v1");
    expect(model.providerID).toBe("cliproxyapi");
  }
});

test("proxy catalog names and limits win over OpenCode's catalog", () => {
  const model = proxyModel(editor, "https://proxy.test", {
    id: "gpt-test",
    name: "GPT Test",
    context: 272_000,
    output: 128_000,
  });
  expect(model.name).toBe("GPT Test");
  expect(model.limit).toEqual({ context: 272_000, output: 128_000 });
  // A model unknown to both catalogs keeps the plugin defaults.
  const unknown = proxyModel(editor, "https://proxy.test", {
    id: "unknown",
    name: "unknown",
  });
  expect(unknown.limit).toEqual({ context: 200_000, output: 32_000 });
});

test("proxy input, efforts, and effort updates win over OpenCode's catalog", () => {
  const model = proxyModel(editor, "https://proxy.test", {
    id: "gpt-test",
    name: "GPT Test",
    input: ["text", "image"],
    efforts: ["low", "high", "ultra"],
    defaultEffort: "high",
    effortUpdates: false,
  });
  expect(model.capabilities.input).toEqual(["text", "image"]);
  expect(model.variants.map((variant) => variant.id)).toEqual([
    "low",
    "high",
    "ultra",
  ]);
  expect(model.variants[0]).toEqual({
    id: "low",
    settings: { reasoningEffort: "low" },
  });
  expect(model.variants[2]).toEqual({
    id: "ultra",
    settings: {
      reasoningEffort: "ultra",
      reasoningSummary: "auto",
      include: ["reasoning.encrypted_content"],
    },
  });
  expect(model.settings.reasoningEffort).toBe("high");
  expect(model.compatibility).toEqual({
    supportsPromptCacheKey: true,
    supportsEffortUpdates: false,
  });
});

test("CPA efforts synthesize package-native variants", () => {
  const claude = proxyModel(editor, "https://proxy.test", {
    id: "claude-test",
    name: "Claude",
    efforts: ["high"],
    defaultEffort: "high",
  });
  expect(claude.variants).toEqual([
    {
      id: "high",
      settings: {
        thinking: { type: "adaptive", display: "summarized" },
        effort: "high",
      },
    },
  ]);

  const gemini = proxyModel(editor, "https://proxy.test", {
    id: "gemini-test",
    name: "Gemini",
    efforts: ["minimal"],
    defaultEffort: "minimal",
  });
  expect(gemini.variants).toEqual([
    {
      id: "minimal",
      settings: {
        thinkingConfig: { thinkingLevel: "minimal", includeThoughts: true },
      },
    },
  ]);

  const grok = proxyModel(editor, "https://proxy.test", {
    id: "grok-test",
    name: "Grok",
    efforts: ["xhigh"],
    defaultEffort: "xhigh",
  });
  expect(grok.variants).toEqual([
    {
      id: "xhigh",
      settings: {
        reasoningEffort: "xhigh",
        reasoningSummary: "auto",
        include: ["reasoning.encrypted_content"],
      },
    },
  ]);

  const unknown = proxyModel(editor, "https://proxy.test", {
    id: "unknown",
    name: "unknown",
    efforts: ["minimal", "ultra"],
    defaultEffort: "minimal",
  });
  expect(unknown.variants).toEqual([
    { id: "minimal", settings: { reasoningEffort: "minimal" } },
    { id: "ultra", settings: { reasoningEffort: "ultra" } },
  ]);
  expect(unknown.settings.reasoningEffort).toBe("minimal");
});

test("registers the Codex catalog, honoring client_version and visibility", async () => {
  const dir = await mkdtemp(join(tmpdir(), "cliproxyapi-test-"));
  const secretPath = join(dir, "credential");
  await writeFile(secretPath, "test-value");
  let requestUrl;
  const server = Bun.serve({
    port: 0,
    fetch: (request) => {
      requestUrl = new URL(request.url);
      return Response.json({
        models: [
          {
            slug: "gpt-test",
            display_name: "GPT Test",
            context_window: 272_000,
            max_tokens: 128_000,
            input_modalities: ["text", "image", "audio"],
            supported_reasoning_levels: [
              { effort: "low" },
              { effort: "ultra" },
              { effort: "ultra" },
            ],
            default_reasoning_level: "ultra",
            supports_reasoning_effort_updates: true,
            priority: 1,
            visibility: "list",
          },
          {
            slug: "claude-test",
            display_name: "Claude Test",
            visibility: "list",
          },
          {
            slug: "aaa-test",
            display_name: "Alphabetical Test",
            priority: 999,
            visibility: "list",
          },
          { slug: "tts-test", display_name: "TTS Test", visibility: "hide" },
        ],
      });
    },
  });
  let registration;
  let cleanup;
  try {
    cleanup = await plugin.setup({
      options: {
        baseUrl: `http://127.0.0.1:${server.port}`,
        cat: "cat",
        codexVersion: "0.0.0",
        apiKeyPath: secretPath,
        cfAccessIdPath: secretPath,
        cfAccessSecretPath: secretPath,
      },
      provider: {
        transform: (transform) =>
          transform({
            ...editor,
            remove() {},
            add(value) {
              registration = value;
            },
          }),
      },
    });
    expect(requestUrl.pathname).toBe("/v1/models");
    expect(requestUrl.searchParams.get("client_version")).toBe("0.0.0");
    expect(registration.info.settings.transport).toBe("websocket");
    expect(registration.info.headers["CF-Access-Client-Id"]).toBe("test-value");
    expect(registration.models.map((model) => model.id)).toEqual([
      "aaa-test",
      "claude-test",
      "gpt-test",
    ]);
    const gpt = registration.models.find((model) => model.id === "gpt-test");
    expect(gpt.package).toBe("@opencode/ai/providers/openai/responses");
    expect(gpt.name).toBe("GPT Test");
    expect(gpt.limit).toEqual({ context: 272_000, output: 128_000 });
    expect(gpt.capabilities.input).toEqual(["text", "image"]);
    expect(gpt.variants.map((variant) => variant.id)).toEqual(["low", "ultra"]);
    expect(gpt.settings.reasoningEffort).toBe("ultra");
    expect(gpt.compatibility.supportsEffortUpdates).toBe(true);
    const claude = registration.models.find(
      (model) => model.id === "claude-test",
    );
    expect(claude.package).toBe("@opencode/ai/providers/anthropic");
    expect(claude.name).toBe("Claude Test");
    expect(claude.limit).toEqual({ context: 200, output: 20 });
  } finally {
    cleanup?.();
    server.stop(true);
    await rm(dir, { recursive: true, force: true });
  }
});

test("other vendors retain their native HTTP APIs", () => {
  const model = proxyModel(editor, "https://proxy.test", {
    id: "claude-test",
    name: "claude-test",
  });
  expect(model.package).toBe("@opencode/ai/providers/anthropic");
  expect(model.settings.transport).toBeUndefined();
  expect(
    proxyModel(editor, "https://proxy.test", { id: "unknown", name: "unknown" })
      .package,
  ).toBe("@opencode/ai/providers/openai-compatible");
});
