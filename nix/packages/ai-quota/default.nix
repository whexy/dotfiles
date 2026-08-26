{ pkgs }:

# Fetch quota for direct subscriptions and accounts on the tailnet AI proxy.
#
# Proxy providers use CLIProxyAPI's management /api-call endpoint. Direct
# providers authenticate from their own agenix-provisioned key files.
pkgs.buildGoModule {
  pname = "ai-quota";
  version = "1.0.0";

  src = ./.;

  # Stdlib-only module, no dependencies to vendor.
  vendorHash = null;

  env.CGO_ENABLED = 0;

  meta.mainProgram = "ai-quota";
}
