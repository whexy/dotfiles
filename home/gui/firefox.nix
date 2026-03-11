{ ... }:
{
  programs.firefox = {
    enable = true;
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
