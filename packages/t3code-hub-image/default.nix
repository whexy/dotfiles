{
  pkgs,
  perSystem,
}:

# The T3 server the cluster runs as its MCP hub (clusters-work `t3code-hub`):
# the same t3code-nightly build the hosts run, so the hub and the machines it
# links to move to each nightly together. It runs no agents of its own; MCP
# clients sign in to it, and it acts on the hosts through linked environments.
# The Woodpecker nightly lane publishes it as ghcr.io/whexy/t3code-hub:<version>.
let
  inherit (pkgs) lib;
  t3 = perSystem.self.t3code-nightly;

  # Linked environments is a Labs setting, off by default; without it the hub
  # can neither link nor forward. The server keeps the other keys it finds.
  entrypoint = pkgs.writeShellApplication {
    name = "t3code-hub";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      t3
    ];
    text = ''
      userdata="$T3CODE_HOME/userdata"
      settings="$userdata/settings.json"
      mkdir -p "$userdata" "$HOME"
      [ -e "$settings" ] || echo '{}' >"$settings"
      next=$(mktemp "$settings.XXXXXX")
      jq '.linkedEnvironmentsEnabled = true' "$settings" >"$next"
      mv "$next" "$settings"
      exec t3 serve --host 0.0.0.0 --port 3773 --no-browser
    '';
  };
in
pkgs.dockerTools.streamLayeredImage {
  name = "ghcr.io/whexy/t3code-hub";
  tag = t3.version;
  contents = [
    t3
    pkgs.cacert
  ];
  # Node reads the user database for os.userInfo(); the image has no other.
  extraCommands = ''
    mkdir -p etc tmp
    echo 't3:x:1000:1000::/data/home:/sbin/nologin' >etc/passwd
    echo 't3:x:1000:' >etc/group
  '';
  config = {
    Entrypoint = [ (lib.getExe entrypoint) ];
    User = "1000:1000";
    ExposedPorts."3773/tcp" = { };
    Env = [
      "T3CODE_HOME=/data"
      "HOME=/data/home"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      # The hosts' privacy settings (modules/home/agents/t3code/home.nix).
      "T3CODE_TELEMETRY_ENABLED=false"
      "T3CODE_OTEL_SDK_DISABLED=true"
      "T3CODE_TRACE_MIN_LEVEL=None"
      "T3CODE_TRACE_MAX_FILES=1"
      "T3CODE_TRACE_MAX_BYTES=65536"
    ];
    Labels."org.opencontainers.image.source" = "https://github.com/whexy/dotfiles";
  };
  meta.platforms = [ "x86_64-linux" ];
}
