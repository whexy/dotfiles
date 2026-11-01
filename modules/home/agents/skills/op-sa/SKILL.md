---
name: op-sa
description: Use a credential from Wenxuan's 1Password with the op-sa CLI without its value ever reaching the chat. Use when the user pastes a 1Password item ID (26 lowercase letters and digits, such as ebcowrtac4l4utbjmvffjjgliq), or asks you to use an API key, token, or file they keep in 1Password.
---

# op-sa

`op-sa` reads the 1Password items in the `dotfiles` and `dotfiles-dev`
vaults. It signs in as this machine's read-only service account, so it never
prompts. Given only an item ID, it finds the vault itself.

## The one rule

A secret value must never appear in anything you see: not in command output,
not in a file you read, not in a command line you write, not in your reply. Your
tool output goes into the conversation, and from there into logs and other
services. Once a value has been shown, it has leaked and has to be rotated.

So never print it, `echo` it, `cat` a file holding it, pass it as an argument
(other users can read a command line), or put it in a file inside the repo.
Never write the value into code or config either: refer to the item instead.

## Look before you use

```sh
op-sa show ebcowrtac4l4utbjmvffjjgliq
```

```
magpie gateway key (API_CREDENTIAL), item ebcowrtac4l4utbjmvffjjgliq in vault dotfiles
  field credential [CONCEALED]
```

`show` prints the title, vault, and the names of the fields and files, never
their values. Without a field name, `run` and `read` use the item's only
concealed field or file; when there are several, add `/<field>` (a field's
label or ID, or a file's name), such as `<item>/password`.

## Give it to a command: `run`

```sh
op-sa run MAGPIE_API_KEY=ebcowrtac4l4utbjmvffjjgliq -- \
  sh -c 'curl -fsS -H "Authorization: Bearer $MAGPIE_API_KEY" https://magpie.clusters.work/v1/models'
```

`run` puts each `VAR=<item>[/<field>]` into the command's environment and
nothing else's, and masks the values in its output as
`<concealed by 1Password>`. Prefer it whenever the program can take the secret
from its environment. A value the command changes before printing it (such as
base64) escapes the mask, so still never print it on purpose.

The variable expands only inside the command, so quote the `sh -c` script in
single quotes; double quotes would expand it in your own shell, where it is
empty.

## Pipe it or write it: `read`

`read` prints the raw value on stdout, so its output must go straight into a
pipe or a file, never to the terminal:

```sh
op-sa read <item> | docker login ghcr.io -u whexy --password-stdin
op-sa read <item> | gh secret set NAME --repo whexy/<repo>
(umask 077; op-sa read <item>/key.pem >"$XDG_RUNTIME_DIR/key.pem")
```

To check it worked, print the length or a fingerprint, never the value:
`op-sa read <item> | wc -c`.

A file you write holds the secret in plaintext: write it outside the repo
with mode 600, never read it back, and delete it when the task is done.

## When it fails

- `this home reads no item <id>`: the item is in neither vault, or it is in
  `dotfiles-dev` and this is a root home. Ask the user to move it into
  `dotfiles` or `dotfiles-dev`; you cannot read their other vaults.
- `could not decrypt this home's 1Password service-account token` or `no
1Password service account`: this machine has no service account yet. Tell
  the user; dotfiles' AGENTS.md ("Secrets") describes setting one up.

Every call costs one to three of the 1,000 requests a day all machines share,
so load a secret once per task rather than in a loop.

## Inside dotfiles

dotfiles' own tools load their keys with `op-sa read <name>`, where `<name>`
is a key of `modules/home/onepassword/items.nix`, which holds the item's full
reference so the read costs one request. Pasted IDs suit one-off tasks; add
an `items.nix` entry when a tool should load the key every time it runs.
