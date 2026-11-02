# REA, the reverse-engineering MCP server and CLI, with the engines enabled
# here baked into its wrapper.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents.rea;
  rea = import ./engines.nix {
    inherit
      pkgs
      lib
      cfg
      perSystem
      ;
  };
in
{
  options.dotfiles.agents.rea = {
    enable = lib.mkEnableOption "the REA reverse-engineering MCP server and CLI, with Ghidra";
    browser.enable = lib.mkEnableOption "website analysis and module-import tracing through Chromium";
    android.enable = lib.mkEnableOption "APK decompilation (JADX), resource decoding (Apktool), and adb device tools";
    binary.enable = lib.mkEnableOption "offline ELF layout and recorded-crash tools (pwntools, pwndbg; Linux x64)";
    firmware.enable = lib.mkEnableOption "firmware scanning and extraction (Binwalk, Unblob; Linux)";
    javascript.enable = lib.mkEnableOption "JavaScript source recovery from bundles (Wakaru; Linux)";
    networkCapture.enable = lib.mkEnableOption "native mitmproxy capture decoding (mitmdump; Linux)";
    dotnet.enable = lib.mkEnableOption "ILSpy decompilation of .NET assemblies";
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        REA_JEB_MCP_URL = "http://127.0.0.1:8425/mcp";
      };
      description = ''
        Further `REA_*` settings for engines that cannot come from nixpkgs,
        such as a licensed JEB or IDA install.
      '';
    };
  };

  config = lib.mkIf (config.dotfiles.agents.enable && cfg.enable) {
    home.packages = [ rea.package ];
    home.sessionVariables = rea.sessionVariables;
    # Taken from the package so the instructions match the server's tools.
    dotfiles.agents.skills.packages = [ rea.base ];
    # Registered here rather than by `rea setup`, which would write an
    # npx-pinned entry into every agent's own config.
    dotfiles.agents.mcp.servers.rea = {
      command = lib.getExe rea.package;
      args = [ "mcp" ];
    };
  };
}
