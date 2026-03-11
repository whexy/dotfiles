{
  pkgs,
  darwin ? false,
  ...
}:
{
  programs.firefox = {
    enable = true;
    # On macOS, Firefox is installed via Homebrew cask (properly signed for 1Password).
    # Home Manager only manages profile configuration.
    package = if darwin then null else pkgs.firefox;
    profiles.default = {
      userChrome = builtins.readFile ./firefox/userChrome.css;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
    profiles.default.search = {
      force = true;
      default = "Unduck";
      privateDefault = "Unduck";

      engines = {
        "Unduck" = {
          urls = [
            {
              template = "https://s.dunkirk.sh";
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
        };
      };
    };
  };
}
