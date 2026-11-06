# ai-remote

Open the **`ai` repository that lives on a remote machine** in VS Code, over SSH, using the
official [**Remote - SSH**](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
extension — with **zero secrets in this repository and no script to run**.

This repo is only the *how-to-connect* layer. It contains no code, no credentials, no IP
addresses and no key material. The machine address and the private key both live in `config/`
on your machine, **git-ignored**; VS Code's own ssh client reads the key **in place** from
there — nothing is copied into `~/.ssh` and nothing is committed.

---

## What you get

- `ai-remote.code-workspace` — the entry point. Connects through the `nexus-ai` ssh alias and
  opens `/opt/workspace/ai`, so you can browse the repo, edit files, use the terminal, run
  tests/commands and use Source Control **on the remote machine**, not on your laptop.
- `config/ssh_config.example` — the ssh stanza (host, user, port, key path) you fill in once.
  The key itself sits next to it at `config/id_ed25519`.

---

## Requirements

**On your machine**

- VS Code (any recent version). The `code` CLI is convenient but not required.
- `ms-vscode-remote.remote-ssh` (VS Code offers it when you open the workspace).
- An SSH key pair the remote machine accepts (public half in its `authorized_keys`).

**On the remote machine**

- `sshd` reachable on the configured port, public-key auth enabled.
- `glibc` ≥ 2.28 (Ubuntu 20.04+).
- Outbound HTTPS to `update.code.visualstudio.com` for the first connect (VS Code Server
  download, typically ~130 MB, cached in `~/.vscode-server`).
- A few hundred MB of RAM free for the VS Code Server process and ~1 GB free disk.

---

## Quick start — no script

```bash
git clone https://github.com/nexuslbs/ai-remote.git
cd ai-remote
```

1. **Put your private key in the repo's `config/` folder** (git-ignored, used in place):

   ```bash
   cp ~/.ssh/id_ed25519 config/id_ed25519
   # Windows cmd/PowerShell:  copy "%USERPROFILE%\.ssh\id_ed25519" "config\id_ed25519"
   ```

2. **Create the ssh stanza** and replace the three `<...>` values:

   ```bash
   cp config/ssh_config.example config/ssh_config
   $EDITOR config/ssh_config     # HostName, User, IdentityFile (absolute path to config/id_ed25519)
   ```

3. **Make your ssh client read it** — pick **one**, done once:

   - **a) one line in `~/.ssh/config`** (Windows: `%USERPROFILE%\.ssh\config`), at the top:

     ```
     Include C:/Users/<you>/ai-remote/config/ssh_config
     ```

   - **b) one VS Code USER setting** — no `~/.ssh/config` edit at all.
     *Command Palette → Preferences: Open User Settings (JSON)*:

     ```json
     "remote.SSH.configFile": "C:/Users/<you>/ai-remote/config/ssh_config"
     ```

4. **Open the workspace** — double-click `ai-remote.code-workspace`, or

   ```bash
   code ai-remote.code-workspace
   ```

VS Code connects as `nexus-ai`, installs VS Code Server on the remote the first time, and
shows `/opt/workspace/ai` from the remote filesystem.

---

## Windows notes

VS Code on Windows shells out to the **Windows OpenSSH client**, which reads
`%USERPROFILE%\.ssh\config`. That is the file the `Include` line of option (a) goes into
(Git-Bash's `$HOME` *is* `%USERPROFILE%`). Two things matter:

- **Forward slashes** in every path inside the ssh config (`C:/Users/you/...`), never
  `\c\Users\...`.
- **Key ACL.** Windows OpenSSH refuses a key that other users can read, and a freshly cloned
  folder inherits permissions. If you see `Permissions for '...' are too open`, run once:

  ```
  icacls "C:\Users\you\ai-remote\config\id_ed25519" /inheritance:r /grant:r "%USERNAME%:F"
  ```

- **Do not** set this up from **WSL**: a Linux-side `~/.ssh/config` is not the file VS Code
  on Windows reads.

---

## File layout

```
ai-remote.code-workspace     committed   the VS Code entry point (alias-based, no IP)
.vscode/extensions.json      committed   recommends the official Remote-SSH extension
config/ssh_config.example    committed   the only template: the ssh stanza you fill in
scripts/check-no-secrets.sh  committed   CI guard: no keys, tokens or literal IPs
docs/SECURITY.md             committed   threat model and the "what stays local" contract
config/ssh_config            GIT-IGNORED real stanza: address + absolute key path
config/id_ed25519            GIT-IGNORED the private key itself — read in place by ssh
```

---

## How it works

1. `config/ssh_config` defines `Host nexus-ai` with `IdentityFile` pointing at the key inside
   this repo — `ssh` opens that file directly, so there is no copy to keep in sync:

   ```
   Host nexus-ai
       HostName <your machine>
       User <your user>
       Port 22
       IdentityFile "C:/Users/you/ai-remote/config/id_ed25519"
       IdentitiesOnly yes
       PreferredAuthentications publickey
       StrictHostKeyChecking accept-new
   ```

2. `ai-remote.code-workspace` opens
   `vscode-remote://ssh-remote+nexus-ai/opt/workspace/ai`. Remote-SSH runs your normal
   OpenSSH client, so the alias (not an IP, not a key) is the only thing committed. Change
   the IP or move the key later without touching the repo.

3. VS Code installs **VS Code Server** on the remote on first connect; the folder you see is
   `/opt/workspace/ai` on the remote filesystem.

Why the alias and not a literal address: the repo is public, so `user@<ip>:22` in git would
advertise an SSH endpoint. The alias keeps the address local, and it survives an IP change.

---

## Known constraints of the reference host

Measured on the machine this repo was designed for (2 vCPU / 3.8 GB RAM / 38 GB disk,
Ubuntu, glibc 2.4x):

- **RAM is the binding constraint.** The VS Code Server plus a couple of extensions takes
  roughly 300–700 MB; keep heavy training runs out of the way while a session is open, and do
  not use `/tmp` for scratch (it is a RAM-backed tmpfs on that box).
- **Git credentials are not configured on the remote.** Pull/push from Source Control will
  prompt for a username/password. Use a fine-grained PAT scoped to the target repo
  (contents: read/write) and let git store it on the *remote*
  (`git config --global credential.helper store`), or switch the remote's `origin` to SSH
  with a deploy key. The credential lives on the remote machine — never in this repo.
- First connect downloads VS Code Server; subsequent connects are fast.

---

## Security

Read [`docs/SECURITY.md`](docs/SECURITY.md). Short version:

- No private key, token, password or literal IP address is committed. CI enforces it.
- `scripts/check-no-secrets.sh` (run by CI on every push) fails if a private key, a token
  pattern, a literal IP, or a tracked `config/ssh_config` / `config/id_ed25519` appears.
- The key you use should be **dedicated** to this workflow so it can be revoked on its own.

## License

MIT
