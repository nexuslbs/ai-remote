# Security model

This repository is **public** and must remain **credential-free**. It is a connection
recipe, not a credential store.

## What is versioned vs. what stays local

| Item | In git? | Where |
|---|---|---|
| SSH stanza template (no address, no key) | yes | `config/ssh_config.example` |
| `.code-workspace` entry point (uses the alias) | yes | `ai-remote.code-workspace` |
| Machine address (IP / DNS) | **no** | `config/ssh_config` (git-ignored, referenced by your ssh config) |
| Private key material | **no** | `config/id_ed25519` (git-ignored, ACL-restricted, used **in place** by ssh) |
| GitHub PAT / token for the remote's git | **never** | credential store **on the remote** |

`scripts/check-no-secrets.sh` fails the build if a private-key block, a common token
pattern (`ghp_`, `github_pat_`, `gho_`, `AKIA…`, `xox…`, `sk-…`), a literal IPv4 address, or
a tracked `config/ssh_config` / `config/id_ed25519` ever appears.

## Why the address is not committed

The repo is public. Publishing `user@<ip>:22` turns it into a scan target and links this
project to a specific piece of infrastructure. Keeping only the *alias* in git means:

- a fresh clone learns nothing about where the machine is;
- the address can change without a repo change;
- forking/starring the repo leaks no topology.

## Key handling rules

1. **Dedicated key pair.** Do not reuse a key that also has access to other hosts.
   ```bash
   ssh-keygen -t ed25519 -a 100 -C "vscode@$(hostname)" -f config/id_ed25519
   ssh-copy-id -i config/id_ed25519.pub <user>@<host>
   ```
   The key lives in `config/` so the installer can point ssh at it without copying
   anything: `config/id_ed25519*` and `config/*.pem|key|ppk` are git-ignored, and
   `scripts/check-no-secrets.sh` **fails** if a key file ever becomes tracked by git.
2. **Never** paste a private key into an issue, a PR, a gist or a chat — even "temporarily".
   If it leaks, rotate: remove the line from the remote `~/.ssh/authorized_keys`
   immediately; the key is single-purpose so nothing else breaks.
3. Because the key sits inside a cloned folder, Windows OpenSSH may reject it as "too open".
   Tighten it once with `icacls "C:\Users\you\ai-remote\config\id_ed25519" /inheritance:r /grant:r "%USERNAME%:F"`
   (POSIX: `chmod 600 config/id_ed25519`).
4. `IdentitiesOnly yes` and `PreferredAuthentications publickey` are set in
   `config/ssh_config` so the client offers only the intended key.
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
