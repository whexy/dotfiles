# cmux integration for AI coding agents.
#
# cmux is a macOS terminal/browser/agent workspace. When the host runs it, the
# agents gain skills that describe how to drive it, and pi gains the session
# extension cmux uses to track turns. Everything here is inert on hosts without
# `dotfiles.terminal.cmux.enable`.
{
  pkgs,
  config,
  lib,
  inputs,
  osConfig,
}:
let
  enable = (osConfig.dotfiles.terminal.cmux.enable or false) && pkgs.stdenv.hostPlatform.isDarwin;

  appRoot = "/Applications/cmux.app/Contents/Resources";

  # The end-user set published at https://cmux.com/docs/skills. Upstream's
  # remaining skills (architecture, backend, billing, release, testing, ...)
  # document cmux development and would cost context for no benefit here.
  # cmux-keyboard-shortcuts is not on that page but is user-facing, and it
  # carries the shortcut templates cmux-settings only exposes as raw paths.
  wanted = [
    "cmux"
    "cmux-browser"
    "cmux-customization"
    "cmux-diagnostics"
    "cmux-keyboard-shortcuts"
    "cmux-markdown"
    "cmux-settings"
    "cmux-workspace"
  ];

  upstream = lib.genAttrs wanted (name: "${inputs.cmux-skills}/skills/${name}");

  # cmux-cua is shipped inside the app bundle and its instructions are tied to
  # the bundled computer-use helper, so the installed build is the only correct
  # version. Link the bundle rather than the pinned checkout, which would drift
  # whenever the app updates ahead of flake.lock.
  bundled = {
    cmux-cua = config.lib.file.mkOutOfStoreSymlink "${appRoot}/cmux-cua";
  };
in
{
  skills = lib.optionalAttrs enable (upstream // bundled);

  # cmux owns this extension and rewrites it in place on every app update, so
  # it cannot be a read-only store symlink. Re-running the installer is the
  # supported way to keep it in step with the installed app.
  activation = lib.optionalAttrs enable {
    cmuxPiHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x "${appRoot}/bin/cmux" ]; then
        run "${appRoot}/bin/cmux" hooks pi install -y || \
          warnEcho "cmux hooks pi install failed; pi session telemetry stays disabled"
      fi
    '';
  };
}
