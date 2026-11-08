{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  # AWS runs credential_process without a shell, so the agenix path expands
  # in this script instead.
  credentials = pkgs.writeShellScript "aws-credentials" ''
    exec ${pkgs.coreutils}/bin/cat ${flake.lib.secretEnv.quote config.age.secrets.aws-credentials.path}
  '';
in
{
  config = lib.mkIf config.dotfiles.tooling.aws.enable {
    age.secrets.aws-credentials.file = ../../../secrets/aws-credentials.age;
    programs.awscli = {
      enable = true;
      settings.default.credential_process = "${credentials}";
    };
  };
}
