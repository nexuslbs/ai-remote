# Security model

This repository is **public** and must remain **credential-free**. It is a connection
recipe, not a credential store.

## What is versioned vs. what stays local

| Item | In git? | Where |
|---|---|---|
| SSH alias definition (template logic) | yes | `scripts/setup.sh` |
| `.code-workspace` entry point (uses the alias) | yes | `ai-remote.code-workspace` |
| Machine address (IP / DNS) | **no** | `config/host.env` (git-ignored) |
| Private-key **path** | **no** | `config/key.path` (git-ignored) |
| Private key material | **never** | your `~/.ssh`, `chmod 600` |
| GitHub PAT / token for the remote's git | **never** | credential store **on the remote** |

`scripts/check-no-secrets.sh` fails the build if a private-key block, a common token
pattern (`ghp_`, `github_pat_`, `gho_`, `AKIA…`, `xox…`, `sk-…`), a literal IPv4 address, or
a tracked `config/host.env` / `config/key.path` ever appears.

## Why the address is not committed

The repo is public. Publishing `user@<ip>:22` turns it into a scan target and links this
project to a specific piece of infrastructure. Keeping only the *alias* in git means:

- a fresh clone learns nothing about where the machine is;
- the address can change without a repo change;
- forking/starring the repo leaks no topology.

## Key handling rules

1. **Dedicated key pair.** Do not reuse a key that also has access to other hosts.
   ```bash
   ssh-keygen -t ed25519 -a 100 -C "vscode@$(hostname)" -f ~/.ssh/id_ed25519_nexus_ai
   ssh-copy-id -i ~/.ssh/id_ed25519_nexus_ai.pub <user>@<host>
   ```
2. **Never** paste a private key into an issue, a PR, a gist or a chat — even "temporarily".
   If it leaks, rotate: remove the line from the remote `~/.ssh/authorized_keys`
   immediately; the key is single-purpose so nothing else breaks.
3. `setup.sh` refuses to run if the key file is missing and tightens permissions to `600`.
4. `IdentitiesOnly yes` and `PreferredAuthentications publickey` are set in the generated
   fragment so the client offers only the intended key.
5. Optional hardening on the remote: restrict the entry with
   `from="<your-ip>",restrict` in `authorized_keys`, or a dedicated non-root user that owns
   the repo directory.

## Account hygiene note

If the SSH user is `root` (as on the reference host), anyone holding the key is root on that
machine. That is a deliberate trade-off for a single-operator research box; reduce it by
creating a normal user, `chown`-ing the working directory to it, and disabling root login.

## Reporting

Open a private security advisory on this repository, or contact the organization owners.
Do not open a public issue containing live infrastructure details.
