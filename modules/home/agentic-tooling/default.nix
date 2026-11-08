# Agentic tooling: programs that coding agents drive, each with the skills
# and MCP servers it adds to every agent. Agents themselves are configured in
# the `agents` group, which never names these tools.
args@{ config, lib, ... }:
let
  cfg = config.dotfiles.agenticTooling;
in
{
  imports = [
    ./rea/default.nix
    ./video/default.nix
    ./formal-verification/default.nix
    ./iphone/default.nix
    ./spark/default.nix
    ./transcribe/default.nix
    ./wechat/default.nix
    ./tldraw/default.nix
  ];

  options.dotfiles.agenticTooling = {
    rea = {
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

    video = {
      enable = lib.mkEnableOption "the video-editing toolkit, driving DaVinci Resolve Studio on macOS or from WSL";
      studio.enable = lib.mkOption {
        type = lib.types.bool;
        # B-roll slots take generated footage from it.
        default = cfg.video.enable;
        defaultText = lib.literalExpression "config.dotfiles.agenticTooling.video.enable";
        description = ''
          Whether to register SimpleStudio's MCP server, which generates video
          on the studio's GPU Workers. Each agent signs in to it once per
          machine, through Cloudflare Access.
        '';
      };
    };

    iphoneUse = {
      enable = lib.mkEnableOption ''
        iPhone Use for every agent: its tools drive one of `phones`, chosen
        by the user per session, through the WebDriverAgent each phone runs
        on its Tailscale address
      '';
      phones = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              host = lib.mkOption {
                type = lib.types.str;
                description = "The phone's MagicDNS name.";
              };
              deviceName = lib.mkOption {
                type = lib.types.str;
                description = "The name set on the phone, which `iphone-wda` finds it by on a paired Mac.";
              };
              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "What the agent shows the user when asking which phone to use.";
              };
            };
          }
        );
        default = import ./iphone/phones.nix;
        defaultText = lib.literalExpression "import ./iphone/phones.nix";
        description = "The iPhones agents can drive, by the name the agent shows.";
      };
      wda = {
        teamId = lib.mkOption {
          type = lib.types.str;
          default = "26DMRHRW6Z";
          description = "Apple development team that signs WebDriverAgent.";
        };
        bundleId = lib.mkOption {
          type = lib.types.str;
          default = "dev.whexy.iphoneuse.wda";
          description = "WebDriverAgent's bundle ID; the runner installs as `<bundleId>.xctrunner`.";
        };
      };
    };

    spark = {
      enable = lib.mkEnableOption "the Spark skill, which searches and reads mail through the `spark` CLI that Spark Desktop installs";
      server = {
        enable = lib.mkEnableOption ''
          spark-mcp, which serves Spark Desktop's email-reading tools to MCP
          clients off this Mac. A Cloudflare tunnel publishes it at
          `https://<host>-spark.clusters.work/mcp` (`flake.lib.publicHost`),
          behind a Cloudflare Access application that admits clients by
          OAuth or service token
        '';
        accessAud = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            AUD tag of the Cloudflare Access application covering this host's
            spark-mcp hostname. The server admits only requests carrying an
            Access assertion for it. The tag identifies the application; it
            is not a secret.
          '';
        };
      };
    };

    formalVerification.enable = lib.mkEnableOption "formal verification with TLA+, and the skills that choose a verifier and keep its checks in step with the code";
    transcribe.enable = lib.mkEnableOption "transcribe, which turns recordings into word-timed transcripts, with its skill";
    wechat.enable = lib.mkEnableOption "wechat, which messages the user on WeChat, with its skill";

    tldraw.enable = lib.mkOption {
      type = lib.types.bool;
      # The server only resolves on the tailnet, so registering it elsewhere
      # leaves every agent with a permanently failing MCP server. Standalone
      # homes have no osConfig to say whether this machine is on the tailnet,
      # but a home with a tailnet relay reaches it through that.
      default = args.osConfig.dotfiles.network.tailscale.enable or config.dotfiles.tailnetRelay.enable;
      defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or config.dotfiles.tailnetRelay.enable";
      description = "Whether to give agents the tailnet tldraw whiteboard's MCP server and the draw skill.";
    };
  };
}
