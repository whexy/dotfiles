{
  pkgs,
  lib,
  config,
  proxyAccounts,
  models,
  aiProxyExtension,
  defaults,
  mcp,
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
    "npm:@monopi/extension-worktree"
  ]
  # pi ships no MCP client by design; the adapter adds one that keeps server
  # tool definitions out of the context window until they are searched.
  ++ lib.optional (mcp.servers != { }) "npm:pi-mcp-adapter";

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
      # The generated extension, not the bare source: the source alone reads a
      # config that only the generator injects.
      ++ lib.optional proxyAccounts "${aiProxyExtension}";

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
        # Native children keep the operator-wide rules as well as project rules.
        scout.inheritGlobalContext = true;
        researcher.inheritGlobalContext = true;
        worker.inheritGlobalContext = true;
        reviewer.inheritGlobalContext = true;
        oracle.inheritGlobalContext = true;
        delegate.inheritGlobalContext = true;
        evidence-auditor.inheritGlobalContext = true;

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
            "bash"
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
  enabledModels = map (model: model.id) models;
  modelThinkingLevels = builtins.listToAttrs (
    map (model: lib.nameValuePair model.id model.thinkingLevel) (
      lib.filter (model: model.thinkingLevel != null) models
    )
  );
}
