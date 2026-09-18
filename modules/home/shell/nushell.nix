# Nushell base configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  config = lib.mkIf cfg.nushell.enable {
    programs.nushell = {
      enable = true;

      configFile.text = ''
        $env.config = {
          show_banner: false
          table: {
            mode: rounded
            index_mode: always
            show_empty: true
            padding: { left: 1, right: 1 }
            trim: {
              methodology: wrapping
              wrapping_try_keep_words: true
            }
          }
          completions: {
            case_sensitive: false
            quick: true
            partial: true
            algorithm: "fuzzy"
            external: {
              enable: true
              max_results: 100
            }
          }
          history: {
            max_size: 10000
            sync_on_enter: true
            file_format: "plaintext"
          }
        }
      '';
    };

    programs.ssh = lib.mkDefault {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          AddKeysToAgent = "yes";
        };
      };
    };
  };
}
