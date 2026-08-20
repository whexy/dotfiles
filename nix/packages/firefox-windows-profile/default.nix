{ pkgs }:

# Plain-file Firefox configuration for Windows, generated from the same
# source of truth as the Home Manager module (nix/modules/home/browser/
# firefox.nix). Built on the WSL host and installed by `just firefox-windows`.
#
# Bundle layout:
#   user.js                    -> %APPDATA%\Mozilla\Firefox\Profiles\*\user.js
#   chrome/userChrome.css      -> <profile>\chrome\userChrome.css
#   policies.json              -> <Firefox install>\distribution\policies.json
#   Install-FirefoxConfig.ps1  -> PowerShell installer (self-elevating)
let
  inherit (pkgs) lib;
  shared = import ../../modules/home/browser/firefox/shared.nix;

  userJs = pkgs.writeText "user.js" (
    ''
      // Managed by Nix (firefox-windows-profile). Regenerate with
      // `just firefox-windows` on the WSL host; manual edits are overwritten.
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: "user_pref(${builtins.toJSON name}, ${builtins.toJSON value});"
      ) shared.settings
    )
  );

  # Home Manager writes search engines into the profile's search.json.mozlz4,
  # but that file carries a verification hash tied to the local profile path,
  # so it cannot be reused across machines. The SearchEngines enterprise
  # policy (Firefox 139+) is the portable equivalent on Windows.
  policiesJson = pkgs.writeText "policies.json" (
    builtins.toJSON {
      policies = shared.policies // {
        SearchEngines = {
          Add = lib.mapAttrsToList (
            name: engine:
            {
              Name = name;
              URLTemplate = engine.url;
            }
            // lib.optionalAttrs (engine ? suggestUrl) { SuggestURLTemplate = engine.suggestUrl; }
          ) shared.search.engines;
          Default = shared.search.default;
        };
      };
    }
  );
in
pkgs.runCommand "firefox-windows-profile" { } ''
  mkdir -p $out/chrome
  cp ${userJs} $out/user.js
  cp ${shared.userChrome} $out/chrome/userChrome.css
  cp ${policiesJson} $out/policies.json
  cp ${./Install-FirefoxConfig.ps1} $out/Install-FirefoxConfig.ps1
  cp ${./README.md} $out/README.md
''
