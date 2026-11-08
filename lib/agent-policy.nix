# What agents may do with the Nix store, rendered into each agent's own
# policy format: they read the sources of everything installed, and never
# edit the store.
let
  readable = [ "/nix/store/**" ];
  readOnly = [ "/nix/store/**" ];
in
{
  inherit readable readOnly;

  # Claude Code's managed policy on system hosts, and the settings every home
  # maintains.
  claude = {
    permissions = {
      allow = map (path: "Read(${path})") readable;
      deny = map (path: "Edit(${path})") readOnly;
    };
    # API-key sessions otherwise get 5-minute prompt caches.
    promptCacheTtl = "1h";
  };
}
