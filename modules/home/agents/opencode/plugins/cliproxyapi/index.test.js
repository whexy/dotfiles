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
      models: new Map([["claude-test", { name: "Claude", settings: {} }]]),
    },
  ],
};

test("GPT models explicitly use Responses WebSocket, including new catalog IDs", () => {
  for (const id of ["gpt-test", "gpt-unknown"]) {
    const model = proxyModel(editor, "https://proxy.test", id);
    expect(model.package).toBe("@opencode/ai/providers/openai/responses");
    expect(model.settings.baseURL).toBe("https://proxy.test/v1");
    expect(model.providerID).toBe("cliproxyapi");
  }
});

test("registers WebSocket transport at the provider boundary", async () => {
  const dir = await mkdtemp(join(tmpdir(), "cliproxyapi-test-"));
  const secretPath = join(dir, "credential");
  await writeFile(secretPath, "test-value");
  const server = Bun.serve({
    port: 0,
    fetch: () =>
      Response.json({ data: [{ id: "gpt-test" }, { id: "claude-test" }] }),
  });
  let registration;
  let cleanup;
  try {
    cleanup = await plugin.setup({
      options: {
        baseUrl: `http://127.0.0.1:${server.port}`,
        cat: "cat",
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
    expect(registration.info.settings.transport).toBe("websocket");
    expect(registration.info.headers["CF-Access-Client-Id"]).toBe("test-value");
    expect(
      registration.models.find((model) => model.id === "gpt-test").package,
    ).toBe("@opencode/ai/providers/openai/responses");
    expect(
      registration.models.find((model) => model.id === "claude-test").package,
    ).toBe("@opencode/ai/providers/anthropic");
  } finally {
    cleanup?.();
    server.stop(true);
    await rm(dir, { recursive: true, force: true });
  }
});

test("other vendors retain their native HTTP APIs", () => {
  const model = proxyModel(editor, "https://proxy.test", "claude-test");
  expect(model.package).toBe("@opencode/ai/providers/anthropic");
  expect(model.settings.transport).toBeUndefined();
  expect(proxyModel(editor, "https://proxy.test", "unknown").package).toBe(
    "@opencode/ai/providers/openai-compatible",
  );
});
