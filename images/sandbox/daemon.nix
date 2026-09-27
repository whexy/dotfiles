{ pkgs, inputs }:
let
  src = inputs.n8n-sandbox-service;
in
pkgs.buildGoModule {
  pname = "n8n-sandbox-daemon";
  version = pkgs.lib.fileContents "${src}/VERSION";
  inherit src;

  vendorHash = "sha256-ZMfmbBESccC7XjrFQ4sFCd8yOVICR2ppCnlSA3T95cU=";
  subPackages = [ "cmd/daemon" ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    mv $out/bin/daemon $out/bin/sandbox-daemon
  '';

  meta = {
    description = "HTTP daemon that runs commands and file operations inside an n8n sandbox";
    homepage = "https://github.com/n8n-io/n8n-sandbox-service";
    license = pkgs.lib.licenses.sustainableUse;
    mainProgram = "sandbox-daemon";
    platforms = pkgs.lib.platforms.linux;
  };
}
