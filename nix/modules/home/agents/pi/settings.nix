{
  pkgs,
  lib,
  config,
  apiAccounts,
  proxyAccounts,
  defaults,
}:
let
  # Keep cycling order and per-model thinking defaults in one ordered list.
  model = id: thinkingLevel: { inherit id thinkingLevel; };
  models = [
    # (DEFAULT, 54) Claude Opus 5
    (model "ai-proxy/claude-opus-5" "high")
    # (55) GPT-6 Astra
    (model "ai-proxy/gpt-6-astra" "low")
    # (57) Claude Fable 5.1
    (model "ai-proxy/claude-fable-5-1" "medium")
    # (53) Muse Spark 1.3
    (model "openrouter/meta/muse-spark-1.3-contributor" null)
    # (51) GPT-5.6 Sol
    (model "ai-proxy/gpt-5.6-sol" "high")
    # (51) Grok 4.6
    (model "ai-proxy/grok-4.6" "high")
    # (50) Kimi K3
    (model "ai-proxy/kimi-k3-256k" "max")
    (model "ai-proxy/kimi-k3" "max")
    (model "openrouter/moonshotai/kimi-k3" "max")
    # (49) GLM 5.3
    (model "openrouter/z-ai/glm-5.3" "max")
    # (47) Gemini 3.8 Flash
    (model "ai-proxy/gemini-3.8-flash" "high")

    # Two cheap models for simpler task
    # (46) GLM-5.3-Flash
    (model "openrouter/z-ai/glm-5.3-flash" null)
    # (43) GPT-5.6 Luna
    (model "ai-proxy/gpt-5.6-luna" "max")

    # API billing (paid by lab)
    (model "openai/gpt-6-astra" null)
    (model "openai/gpt-5.6-sol" null)
    (model "openai/gpt-5.6-terra" null)
    (model "openai/gpt-5.6-luna" null)
    (model "anthropic/claude-fable-5-1" null)
    (model "anthropic/claude-opus-5" null)
    (model "anthropic/claude-sonnet-5" null)
  ];
  modelEnabled =
    model:
    if lib.hasPrefix "ai-proxy/" model.id then
      proxyAccounts
    else if lib.hasPrefix "openai/" model.id || lib.hasPrefix "anthropic/" model.id then
      apiAccounts
    else
      true;
  enabledModels = lib.filter modelEnabled models;
in
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
  enabledModels = map (model: model.id) enabledModels;
  modelThinkingLevels = builtins.listToAttrs (
    map (model: lib.nameValuePair model.id model.thinkingLevel) (
      lib.filter (model: model.thinkingLevel != null) enabledModels
    )
  );
}
