# Every agent harness, rendered from `dotfiles.agents.harnesses`: its
# launcher, the global rules in its instructions file, its skill root, and,
# for agents agent-settings manages, the model picker and the activation that
# reconciles their native settings. Each agent's own module only declares
# its entry.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
  agentSettings = lib.getExe perSystem.self.agent-settings;

  harness = lib.types.submodule (
    { name, ... }:
    {
      options = {
        package = lib.mkOption {
          type = lib.types.package;
          description = "The agent's own package.";
        };
        binary = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "The program in the package's `bin` the launcher, named after the harness, starts.";
        };
        prelude = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Shell lines the launcher runs after `dotfiles.agents.launcher.prelude`.";
        };
        rules = {
          file = lib.mkOption {
            type = lib.types.str;
            description = "Home-relative path of the instructions file holding the global rules.";
          };
          extraText = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Instructions for this agent alone, after the global rules.";
          };
        };
        skillsRoot = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Home-relative directory the agent reads user skills from.";
        };
        settings = lib.mkOption {
          default = null;
          description = ''
            How agent-settings manages the agent's native settings, which stay
            writable: only the catalog and policy inputs live in the store. The
            launcher then starts the agent through agent-settings, and the
            harness gains `<name>-select` and `<name>-settings-sync`.
          '';
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                entries = lib.mkOption {
                  type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
                  description = "The model picker's entries.";
                };
                mcpFormat = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  description = "Shape of the MCP servers agent-settings maintains, a key of `dotfiles.agents.mcp.rendered`.";
                };
                maintainedSettings = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                  description = "Settings every reconciliation maintains.";
                };
                resetEnv = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Variables a selection takes over from the caller's environment.";
                };
                managedLinks = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Files in the config directory a forked config links back to the default's.";
                };
              };
            }
          );
        };
      };
    }
  );

  wrap =
    name: h:
    let
      launcher = pkgs.writeShellScriptBin name ''
        ${cfg.launcher.prelude + h.prelude}
        exec ${if h.settings == null then lib.getExe' h.package h.binary else "${runtime} launch"} "$@"
      '';
      manifest = pkgs.writeText "${name}-settings-catalog.json" (
        builtins.toJSON {
          inherit name;
          inherit (h.settings)
            entries
            maintainedSettings
            resetEnv
            managedLinks
            ;
          mcpServers = cfg.mcp.rendered.${h.settings.mcpFormat};
          real = "${h.package}/bin/${h.binary}";
        }
      );
      runtime = "${agentSettings} ${manifest}";
      selector = pkgs.writeShellScriptBin "${name}-select" ''
        exec ${runtime} select ${launcher}/bin/${name} "$@"
      '';
      sync = pkgs.writeShellScriptBin "${name}-settings-sync" ''
        exec ${runtime} sync "$@"
      '';
    in
    # The launcher stands in for the program it starts, which run directly
    # would skip the prelude.
    pkgs.runCommand (if h.settings == null then name else "${name}-settings")
      { meta.mainProgram = name; }
      (
        ''
          mkdir -p $out/bin
          for p in ${h.package}/*; do
            if [ "$(basename "$p")" != bin ]; then
              ln -s "$p" $out/
            fi
          done
          for p in ${h.package}/bin/*; do
            if [ "$(basename "$p")" != ${h.binary} ]; then
              ln -s "$p" $out/bin/
            fi
          done
          ln -s ${launcher}/bin/${name} $out/bin/${name}
        ''
        + lib.optionalString (h.settings != null) ''
          ln -s ${selector}/bin/${name}-select $out/bin/${name}-select
          ln -s ${sync}/bin/${name}-settings-sync $out/bin/${name}-settings-sync
        ''
      );

  wrapped = lib.mapAttrs wrap cfg.harnesses;
  managed = lib.filterAttrs (_: h: h.settings != null) cfg.harnesses;
in
{
  options.dotfiles.agents = {
    harnesses = lib.mkOption {
      type = lib.types.attrsOf harness;
      default = { };
      description = "The agents installed, keyed by the command that launches each.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = lib.attrValues wrapped;

      file = lib.mapAttrs' (
        _: h:
        lib.nameValuePair h.rules.file (
          if h.rules.extraText == "" then
            { source = ./global-rules.md; }
          else
            { text = builtins.readFile ./global-rules.md + "\n" + h.rules.extraText; }
        )
      ) cfg.harnesses;

      activation = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${name}Settings" (
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            run ${wrapped.${name}}/bin/${name}-settings-sync
          ''
        )
      ) managed;
    };
  };
}
