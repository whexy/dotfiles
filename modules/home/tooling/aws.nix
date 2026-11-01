{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.dotfiles.tooling.aws.enable {
    programs.awscli = {
      enable = true;
      settings.default.credential_process = "${lib.getExe config.dotfiles.onepassword.package} read aws-credentials";
    };
  };
}
