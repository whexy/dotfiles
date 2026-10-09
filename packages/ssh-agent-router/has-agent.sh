#!/bin/sh
# OpenSSH runs this `Match exec` check on every connection, so it must stay a
# cheap shell test. Only an inbound SSH session carries a forwarded or proxied
# agent. A local desktop's SSH_AUTH_SOCK belongs to another agent (gcr,
# gpg-agent) and must not displace the 1Password IdentityAgent.
[ -n "${SSH_CONNECTION-}" ] && [ -n "${SSH_AUTH_SOCK-}" ]
