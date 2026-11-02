# The managed policy the T3 Code server applies, and the setting activation
# writes in its place where the server ignores policies.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  policyCfg = config.programs.t3code.policy;
  json = pkgs.formats.json { };

  # Upstream's prebuilt server ignores T3CODE_DEV_MANAGED_POLICY_PATH; a
  # package whose server reads it says so with passthru.honorsManagedPolicyPath.
  # Any other server gets no policy, so none looks applied.
  honorsPolicy = cfg.package.honorsManagedPolicyPath or false;

  userdataSetting = import ./userdata.nix {
    inherit lib pkgs;
    inherit (config.home) homeDirectory;
  };

  # The policy locks linked environments on. Where the server runs without a
  # policy, activation writes the setting instead; the running server reloads
  # settings.json when it changes.
  linkedEnvironments = userdataSetting {
    name = "t3-linked-environments";
    file = "settings.json";
    key = "linkedEnvironmentsEnabled";
    value = true;
  };
in
{
  # Home Manager's own programs.t3code installs a package and merges
  # settings; the policy applies to the server dotfiles.t3code runs.
  options.programs.t3code.policy = lib.mkOption {
    inherit (json) type;
    default = { };
    description = ''
      The T3 Code managed policy for the server dotfiles.t3code runs, as T3's
      JSON document; empty means none. Setting paths are literal dotted keys.
      The server reads it from the Nix store, where agents running as the
      user cannot change it, and restarts when it changes. A server package
      without `passthru.honorsManagedPolicyPath` ignores the policy, so
      none is set for it, and a policy given anyway warns.
    '';
  };

  options.dotfiles.t3code.policyFile = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    internal = true;
    readOnly = true;
    # The `t3` that loads the policy checks it first; it is the only check, as
    # the option itself is plain JSON.
    default =
      if policyCfg == { } || !honorsPolicy then
        null
      else
        let
          unchecked = json.generate "t3code-policy-unchecked.json" policyCfg;
        in
        pkgs.runCommand "t3code-policy.json" { } ''
          HOME=$TMPDIR ${lib.getExe' cfg.finalPackage "t3"} policy check ${unchecked} >&2
          cp ${unchecked} $out
        '';
    description = "The checked policy in the Nix store, or null where the server runs without one.";
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = policyCfg != { } -> cfg.enable && cfg.server.enable;
          message = "programs.t3code.policy applies only to the server dotfiles.t3code.server runs.";
        }
      ];
      warnings = lib.optional (policyCfg != { } && !honorsPolicy) ''
        programs.t3code.policy is set, but ${cfg.package.name} ignores
        T3CODE_DEV_MANAGED_POLICY_PATH, so the T3 Code server runs without it.
      '';
    }
    (lib.mkIf (cfg.enable && cfg.server.enable) {
      # Each key is a default a home replaces on its own. Locked: linked
      # environments, which the cluster's MCP hub (clusters-work
      # gitops/apps/t3code-hub) needs to link to every server, and provider
      # update checks, as Nix pins the provider CLIs. The rest are preferences
      # the user's own choices override. Telemetry also stays off in the
      # environment, for the desktop app and for servers that ignore the
      # policy. The Claude provider instance stays out: t3-claude-models
      # rewrites its models, and T3 locks an instance only as a whole.
      programs.t3code.policy = lib.mkIf honorsPolicy (
        lib.mapAttrsRecursive (_: lib.mkDefault) {
          schemaVersion = 1;
          organization = "dotfiles";
          limits.telemetry = false;
        }
        // {
          settings =
            lib.mapAttrs (_: lib.mkDefault) {
              "linkedEnvironmentsEnabled" = {
                value = true;
                locked = true;
              };
              "enableProviderUpdateChecks" = {
                value = false;
                locked = true;
              };
            }
            //
              lib.mapAttrs
                (
                  _: value:
                  lib.mkDefault {
                    inherit value;
                    locked = false;
                  }
                )
                {
                  "storageCleanup.worktreeAfterDays" = 8;
                  "storageCleanup.worktreeOnMerge" = true;
                  "storageCleanup.worktreeOnDelete" = true;
                  "storageCleanup.worktreeUnchanged" = true;
                  "storageCleanup.browserArtifactsAfterDays" = 8;
                  "storageCleanup.logsAfterDays" = 8;
                  "defaultAutoPull" = true;
                  "idleCompaction" = "beforeCacheExpires";
                  "snoozeLimitedThreads" = true;
                  "autoResumeLimitedThreads" = true;
                  "sidebarAutoSettleOnMerge" = false;
                  "branchNamingMode" = "semantic";
                  "branchNamePrefix" = "whexy/";
                  "pullRequestMergeMethod" = "rebase";
                };
        }
      );

      # After t3-claude-models, which edits the same file.
      home.activation = lib.mkIf (cfg.policyFile == null) {
        t3codeLinkedEnvironments = lib.hm.dag.entryAfter [ "t3codeClaudeModels" ] ''
          run ${lib.getExe linkedEnvironments}
        '';
      };
    })
  ];
}
