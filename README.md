# ai-remote

Open the **`ai` repository that lives on a remote machine** in VS Code, over SSH, using the
official [**Remote - SSH**](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
extension — with **zero secrets in this repository**.

This repo is only the *how-to-connect* layer. It contains no code, no credentials, no IP
addresses and no key material. The machine address lives in `config/host.env` and the
private-key location lives in `config/key.path`; both are **git-ignored** and created by you
on your own machine.

---

## What you get

- A `.code-workspace` file that connects to the remote host through an SSH alias and opens
  `/opt/workspace/ai` directly, so you can browse the repo, edit files, use the terminal,
  run tests/commands and use Source Control **on the remote machine**, not on your laptop.
- A one-command installer (`scripts/setup.sh`) that renders the SSH alias from your two
  local files and wires it into `~/.ssh/config`.
- A one-command launcher (`scripts/open.sh`) that opens the folder in VS Code through the
  Remote-SSH extension.

---

## Requirements

**On your machine**

- VS Code (any recent version) + the `code` CLI on `PATH`.
- `ms-vscode-remote.remote-ssh` (installed automatically by `scripts/open.sh`).
- An SSH key pair that the remote machine accepts (public half in its `authorized_keys`).

**On the remote machine**

- `sshd` reachable on the configured port, public-key auth enabled.
- `glibc` ≥ 2.28 (Ubuntu 20.04+). `uname -sr` / `ldd --version` to check.
- Outbound HTTPS to `update.code.visualstudio.com` for the first connect (VS Code Server
  download, typically ~130 MB, cached in `~/.vscode-server`).
- A few hundred MB of RAM free for the VS Code Server process and ~1 GB free disk.

---

## Quick start

```bash
git clone https://github.com/nexuslbs/ai-remote.git
cd ai-remote

# 1. tell it where the machine is (git-ignored)
cp config/host.env.example config/host.env
$EDITOR config/host.env          # NEXUS_SSH_HOST=<machine ip or dns>, NEXUS_SSH_USER, NEXUS_SSH_PORT

# 2. tell it where your private key is (git-ignored)
cp config/key.path.example config/key.path
$EDITOR config/key.path          # absolute path, e.g. ~/.ssh/id_ed25519_nexus_ai

# 3. render the SSH alias and test the connection
./scripts/setup.sh

# 4. open the remote repo in VS Code
./scripts/open.sh
```

Or, if you prefer the UI: `File → Open Workspace from File…` → `ai-remote.code-workspace`.

---

## File layout

```
ai-remote.code-workspace     committed   the VS Code entry point (alias-based, no IP)
.vscode/extensions.json      committed   recommends the official Remote-SSH extension
scripts/setup.sh             committed   renders ~/.ssh/config.d/<alias>, tests the connection
scripts/open.sh              committed   installs Remote-SSH if needed, opens the folder
scripts/check-no-secrets.sh  committed   CI/pre-commit guard: no keys, tokens or literal IPs
docs/SECURITY.md             committed   threat model and the "what stays local" contract
config/host.env.example      committed   template: host / user / port / remote path
config/key.path.example      committed   template: absolute path of the private key
config/host.env              GIT-IGNORED real machine address
config/key.path              GIT-IGNORED real private-key path
```

---

## How it works

1. `scripts/setup.sh` reads `config/host.env` + `config/key.path` and writes
   `~/.ssh/config.d/<alias>`:

   ```
   Host nexus-ai
       HostName <from host.env>
       User <from host.env>
       Port <from host.env>
       IdentityFile "<from key.path>"
       IdentitiesOnly yes
       PreferredAuthentications publickey
       StrictHostKeyChecking accept-new
   ```

   and prepends `Include ~/.ssh/config.d/nexus-ai` to `~/.ssh/config`.

2. `ai-remote.code-workspace` opens
   `vscode-remote://ssh-remote+nexus-ai/opt/workspace/ai`. Remote-SSH runs
   `ssh nexus-ai` with your normal OpenSSH client, so the alias (not an IP, not a key)
   is the only thing committed. Change the IP later without touching the repo.

3. VS Code installs **VS Code Server** on the remote on first connect; the folder you see
   is `/opt/workspace/ai` on the remote filesystem.

Why an `Include` instead of `remote.SSH.configFile`: `configFile` does not reliably expand
`${workspaceFolder}`, so pointing it at a repo-relative file is fragile and would require a
per-user setting anyway. Using the default `~/.ssh/config` means **no user settings at all**
are needed — clone, run two scripts, done.

---

## Known constraints of the reference host

Measured on the machine this repo was designed for (2 vCPU / 3.8 GB RAM / 38 GB disk,
Ubuntu 26.04, glibc 2.43):

- **RAM is the binding constraint.** The VS Code Server plus a couple of extensions takes
  roughly 300–700 MB; keep heavy training runs out of the way while you have a session open,
  and do not use `/tmp` for scratch (it is a RAM-backed tmpfs on that box).
- **Git credentials are not configured on the remote.** Pull/push from Source Control will
  prompt for a username/password. Use a fine-grained PAT scoped to the target repo
  (contents: read/write) and let git store it on the *remote* (`git config --global
  credential.helper store`), or switch the remote's `origin` to SSH with a deploy key.
  The credential lives on the remote machine — never in this repo.
- First connect downloads VS Code Server; subsequent connects are fast.

---

## Security

Read [`docs/SECURITY.md`](docs/SECURITY.md). Short version:

- No private key, token, password or literal IP address is committed. CI enforces it.
- The key you use should be **dedicated** to this workflow so it can be revoked on its own.
- Keeping the address out of git avoids advertising an SSH endpoint publicly; the repo is
  public, the infrastructure is not.

## License

MIT
