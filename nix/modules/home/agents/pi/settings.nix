{
  pkgs,
  lib,
  config,
  apiAccounts,
  proxyAccounts,
  defaults,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  inherit (defaults) defaultProvider defaultModel;

  packages = [
    "npm:pi-web-access"
    "npm:@narumitw/pi-goal"
    "npm:pi-subagents"
    "npm:pi-background-tasks"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];

  subagents =
    let
      npmExtension = path: "${config.home.homeDirectory}/.pi/agent/npm/node_modules/${path}";
      # pi-subagents 0.65.0 stopped loading ambient extensions in foreground
      # children, and the background runner that still loads them needs pi from
      # npm rather than this standalone binary. Naming extensions here is the
      # only way children keep web access, background tasks, and the ai-proxy
      # provider that `ai-proxy/*` model overrides resolve against.
      defaultExtensions = [
        (npmExtension "pi-web-access/index.ts")
        (npmExtension "pi-background-tasks/extensions/background-tasks.ts")
      ]
      ++ lib.optional proxyAccounts "${./ai-proxy.ts}";

      # Loading an extension only registers its tools; an agent with an explicit
      # allowlist still drops anything it does not name, so each grant below
      # restates the upstream toolset plus what that role should gain.
      readTools = [
        "read"
        "grep"
        "find"
        "ls"
      ];
      # source_check verifies a claim against sources, which is research work
      # rather than the incidental doc lookup the other roles need.
      lookupTools = [
        "web_search"
        "fetch_content"
        "get_search_content"
      ];
      researchTools = lookupTools ++ [ "source_check" ];
      # bg_wait cannot observe bg_run shell tasks, and a child that ends its
      # turn is shut down with its tasks killed. Children can only poll a task
      # they outlive, so this suits roles that run one long check inline and
      # stay until it finishes. bg_kill lets them release that task early.
      longRunTools = [
        "bg_run"
        "bg_status"
        "bg_logs"
        "bg_kill"
      ];
    in
    {
      inherit defaultExtensions;
      agentOverrides = {
        # Recon reads what is already on disk; a build it cannot outlive would
        # only stall the handoff it exists to produce.
        scout.tools = readTools ++ [
          "bash"
          "write"
          "contact_supervisor"
        ];

        # Upstream already grants the lookup tools; source_check makes claim
        # verification first-class for the one role meant to be cited.
        researcher.tools = [
          "read"
          "write"
        ]
        ++ researchTools;

        # Implementation is the role that genuinely waits on builds and test
        # suites, and needs docs for unfamiliar APIs.
        worker.tools =
          readTools
          ++ [
            "bash"
            "edit"
            "write"
            "contact_supervisor"
          ]
          ++ lookupTools
          ++ longRunTools;

        # Review stays read-only, but running the suite is how a reviewer
        # confirms a change rather than assuming it.
        reviewer.tools =
          readTools
          ++ [
            "contact_supervisor"
          ]
          ++ lookupTools
          ++ longRunTools;

        # The oracle judges a decision packet it was handed. Giving it research
        # or long checks invites the reconnaissance it is explicitly not for.
        oracle.tools = readTools ++ [ "bash" ];

        # A general delegate stands in for the parent, so it gets the same
        # broad access as worker.
        delegate.tools =
          readTools
          ++ [
            "bash"
            "edit"
            "write"
            "contact_supervisor"
          ]
          ++ lookupTools
          ++ longRunTools;
      };
    };

  # Scoped models for Ctrl+P cycling (`/scoped-models`).
  enabledModels =
    let
      models = [
        # (66) Claude Fable 5.1
        "ai-proxy/claude-fable-5-1"
        # (63) Claude Opus 5
        "ai-proxy/claude-opus-5"
        # (62) Muse Spark 1.3
        "openrouter/meta/muse-spark-1.3-contributor"
        # (61) GPT-5.6 Sol, GPT-6-astra
        "ai-proxy/gpt-5.6-sol"
        "ai-proxy/gpt-6-astra"
        # (61) Grok 4.6
        "ai-proxy/grok-4.6"
        # (60) Kimi K3, GLM 5.3
        "ai-proxy/kimi-k3-256k"
        "ai-proxy/kimi-k3"
        "openrouter/moonshotai/kimi-k3"
        "openrouter/z-ai/glm-5.3"
        # (59) Gemini 3.8 Flash
        "ai-proxy/gemini-3.8-flash"
        # (58) Claude Sonnet 5
        "ai-proxy/claude-sonnet-5"

        # Two cheap models for simpler task
        # (57) GLM-5.3-Flash
        "openrouter/z-ai/glm-5.3-flash"
        # (52) GPT-5.6 Luna
        "ai-proxy/gpt-5.6-luna"

        # API billing (payed by lab)
        "openai/gpt-6-astra"
        "openai/gpt-5.6-sol"
        "openai/gpt-5.6-terra"
        "openai/gpt-5.6-luna"
        "anthropic/claude-fable-5-1"
        "anthropic/claude-opus-5"
        "anthropic/claude-sonnet-5"
      ];
      modelEnabled =
        model:
        if lib.hasPrefix "ai-proxy/" model then
          proxyAccounts
        else if lib.hasPrefix "openai/" model || lib.hasPrefix "anthropic/" model then
          apiAccounts
        else
          true;
    in
    lib.filter modelEnabled models;
}
