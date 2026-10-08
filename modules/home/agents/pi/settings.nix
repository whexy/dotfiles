{
  pkgs,
  defaults,
}:
{
  enableInstallTelemetry = false;
  enableAnalytics = false;

  inherit (defaults) defaultProvider defaultModel;

  packages = [
    "npm:pi-web-access"
    "npm:pi-background-tasks"
  ];

  npmCommand = [ "${pkgs.nodejs}/bin/npm" ];
}
