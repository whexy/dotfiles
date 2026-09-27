# Self-expiring overlay: numtide/llm-agents.nix#9966
# node-pty on macOS spawns every shell through its bundled spawn-helper, which
# the t3code package ships without the execute bit. Upstream's chmod walks the
# desktop output, whose node_modules is a symlink into $out that find does not
# follow, so the helper stays 0444 and every T3 Code terminal fails with
# "posix_spawnp failed".
#
# Once the llm-agents input carries the fix (the chmod walks $out), this
# overlay becomes a no-op and emits a warning reminding to remove it.
#
# Requires the `llm-tools` overlay (pkgs.llm-agents) to be applied before this
# one.
_final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin (
  let
    upstream = prev.llm-agents.t3code;
    fixedUpstream =
      builtins.match ''.*find "\$out/libexec/t3code" \\[[:space:]]+-path '\*/node-pty/prebuilds/darwin-\*/spawn-helper'.*'' upstream.unwrapped.installPhase
      != null;
  in
  {
    llm-agents = prev.llm-agents // {
      t3code =
        prev.lib.warnIf fixedUpstream
          ''
            llm-agents now makes t3code's node-pty spawn-helper executable; the
            t3code-spawn-helper overlay can be removed.
          ''
          (
            if fixedUpstream then
              upstream
            else
              upstream.override {
                t3code-unwrapped = upstream.unwrapped.overrideAttrs (old: {
                  postInstall = (old.postInstall or "") + ''
                    find "$out/libexec/t3code" \
                      -path '*/node-pty/prebuilds/darwin-*/spawn-helper' \
                      -exec chmod 755 {} +
                  '';
                });
              }
          );
    };
  }
)
