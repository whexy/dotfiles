# Recipient config for the agenix CLI — NOT imported by any Nix config.
# This file only tells the `agenix` CLI which public keys to encrypt each
# .age file for. The actual secret declarations (which modules consume which
# secrets) live in home/secrets.nix.
#
# Usage:
#   cd secrets/
#   agenix -e api-keys.age    # create/edit the encrypted secret
#   agenix --rekey             # re-encrypt after changing public keys
#
# The api-keys.age file should contain KEY=VALUE lines:
#   ANTHROPIC_API_KEY=sk-ant-...
#   OPENAI_API_KEY=sk-...
let
  # Shared age public key (used across all machines)
  # Generate with: age-keygen -o ~/.config/agenix/key.txt
  # Replace this placeholder with the actual public key from age-keygen output
  key = "age1tmghvzq2kq9seud5uu9hh833g0v4z2356nsqumknfnluawa6qe9qt6k886";
in
{
  "api-keys.age".publicKeys = [ key ];
  "b2-account.age".publicKeys = [ key ];
  "b2-key.age".publicKeys = [ key ];
  "b2-crypt-password.age".publicKeys = [ key ];
  "nas-webdav-pass.age".publicKeys = [ key ];
}
