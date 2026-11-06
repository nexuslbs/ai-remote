# ai-remote

Open the **`ai` repository that lives on a remote machine** in VS Code, over SSH, with the
official [**Remote - SSH**](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
extension — **no script to run, no credentials and no address in git**.

Everything that defines the connection lives **inside this folder**:

- `config/ssh_config` — host, user, port, key path (git-ignored)
- `config/id_ed25519` — the private key itself (git-ignored, read **in place** by ssh)
- `config/known_hosts` — the host key ssh learns on first connect (git-ignored)

Nothing is copied into `~/.ssh`, nothing is written into your VS Code *workspace*, and
nothing is committed. Delete the folder and the connection is gone.

---

## The one line VS Code forces (and why)

VS Code cannot read the ssh-config path from a workspace or project file. That setting is
**machine-scoped** by design, because Remote-SSH has to reach the host *before* any workspace
on it exists:

> "Not really possible because in a Remote-SSH scenario, the workspace is on the remote. And
> you need the ssh config file _before_ you connect to the remote"
> — roblourens (VS Code Remote team),
> [vscode-remote-release#10150](https://github.com/microsoft/vscode-remote-release/issues/10150);
> same request closed twice before: [#7772](https://github.com/microsoft/vscode-remote-release/issues/7772),
> [#10150](https://github.com/microsoft/vscode-remote-release/issues/10150).

So exactly one pointer has to exist outside this folder. It is a **path, nothing else** — no
address, no user, no key:

```json
// VS Code User settings (Preferences: Open User Settings (JSON))
"remote.SSH.configFile": "C:/Users/<you>/ai-remote/config/ssh_config"
```

Uninstall = delete that one line. (If you prefer the ssh-config route instead, the equivalent
is a single `Include C:/Users/<you>/ai-remote/config/ssh_config` line at the top of
`~/.ssh/config`; pick **one**, not both, and delete it to uninstall.)

Everything else stays in the project. See *Zero-machine-state variant* below if even that one
line is too much.

---

## What you get

- `ai-remote.code-workspace` — the entry point. Connects through the `nexus-ai` alias and
  opens `/opt/workspace/ai`, so you can browse the repo, edit files, use the terminal, run
  tests/commands and use Source Control **on the remote machine**, not on your laptop.
- `config/ssh_config.example` — the single template: host, user, port and the path to the key
  that already sits next to it.

---

## Requirements

**On your machine**

- VS Code (any recent version).
- `ms-vscode-remote.remote-ssh` (VS Code offers it when you open the workspace).
- An OpenSSH client (Windows 10+ ships one).
- An SSH key pair the remote machine accepts (public half in its `authorized_keys`).

**On the remote machine**

- `sshd` reachable on the configured port, public-key auth enabled.
- `glibc` ≥ 2.28 (Ubuntu 20.04+), `bash`, `tar`, `curl` or `wget`.
- Outbound HTTPS to `update.code.visualstudio.com` for the first connect (VS Code Server
  download, typically ~130 MB, cached in `~/.vscode-server`).
- A few hundred MB of RAM free for the VS Code Server process and ~1 GB free disk.

---

## Setup

```bash
git clone https://github.com/nexuslbs/ai-remote.git
cd ai-remote
```

1. **Put your private key in the project's `config/` folder** (used in place, never copied):

   ```bash
   cp ~/.ssh/id_ed25519 config/id_ed25519
   # Windows cmd/PowerShell:  copy "%USERPROFILE%\.ssh\id_ed25519" "config\id_ed25519"
   ```

2. **Create `config/ssh_config`** and replace the three `<...>` values:

   ```bash
   cp config/ssh_config.example config/ssh_config
   $EDITOR config/ssh_config     # HostName, User, IdentityFile (absolute path to config/id_ed25519)
   ```

   This file is the whole connection definition. It is git-ignored, so your address never
   reaches a public repo.

3. **Add the one pointer** from *The one line VS Code forces* above — a User setting whose
   value is the path to `config/ssh_config`, or the single `Include` line in `~/.ssh/config`.
   Do it once; it is the only thing outside this folder.

4. **Open the workspace** — double-click `ai-remote.code-workspace`, or `code ai-remote.code-workspace`.

VS Code connects as `nexus-ai`, installs VS Code Server on the remote the first time, and
shows `/opt/workspace/ai` from the remote filesystem.

---

## Check the connection without VS Code

```bash
ssh -F config/ssh_config -o BatchMode=yes nexus-ai "echo OK"
```

`-F` points ssh at the project's file directly, so this test works even before step 3.
`OK` means the key, the address and the remote `authorized_keys` are all correct and anything
still broken is on the VS Code side.

---

## Troubleshooting

### `ENOPRO: No filesystem provider found for resource 'vscode-remote://...'`

The folder shows greyed-out in the Explorer and cannot be opened. This is a **client-side**
resolution failure: at the moment the window tried to load the folder, no `vscode-remote`
filesystem provider existed for `ssh-remote+nexus-ai`. Nothing is wrong on the remote machine.

It means Remote-SSH could not resolve the alias `nexus-ai` — i.e. the pointer from step 3 is
missing, typo'd, or points at a file that does not exist. Check, in this order:

1. The path in `remote.SSH.configFile` (or the `Include` line) is the **absolute** path to
   `config/ssh_config`, with forward slashes (`C:/Users/...`), and the file exists.
2. `Host nexus-ai` is spelled exactly like that inside it (the workspace URI uses that alias).
3. Command Palette → **Developer: Reload Window** — a failed resolution is cached per window.
4. Command Palette → **Remote-SSH: Connect to Host...**: `nexus-ai` must appear in the list.
   If it does not, VS Code is not reading your file at all (step 1).

Note that a `remote.SSH.*` setting placed **inside** `ai-remote.code-workspace` is ignored by
VS Code (the setting is machine-scoped) — the pointer must be a User setting or an `Include`.

### `Permission denied (publickey)`

The address is fine; the remote machine does not authorize this key's public half. Confirm
which key is offered and which is authorized:

```bash
ssh -F config/ssh_config -o BatchMode=yes nexus-ai "echo OK"        # client side
ssh-keygen -lf config/id_ed25519.pub                                # fingerprint to compare
```

Then append `config/id_ed25519.pub` to the remote `~/.ssh/authorized_keys` (an account can
hold several keys, and it is easy to authorize a different one than the config uses).

---

## Windows notes

VS Code on Windows shells out to the **Windows OpenSSH client**, which reads
`%USERPROFILE%\.ssh\config` (Git-Bash's `$HOME` *is* `%USERPROFILE%`). Two things matter:

- **Forward slashes** in every path inside the ssh config (`C:/Users/you/...`), never
  `\c\Users\...`.
- **Key ACL.** Windows OpenSSH refuses a key other users can read, and a freshly cloned
  folder inherits permissions. If you see `Permissions for '...' are too open`:

  ```
  icacls "C:\Users\you\ai-remote\config\id_ed25519" /inheritance:r /grant:r "%USERNAME%:F"
  ```

- **Do not** set this up from **WSL**: a Linux-side `~/.ssh/config` is not the file VS Code
  on Windows reads.

---

## Zero-machine-state variant

If even the single pointer must not exist outside the project, run a VS Code instance whose
*user* settings directory is inside the project — then `remote.SSH.configFile` is itself part
of the folder:

```bash
code --user-data-dir "C:/Users/<you>/ai-remote/.vscode-user-data" ai-remote.code-workspace
```

Write the one setting into that instance's `User/settings.json` (it lives under
`.vscode-user-data/`, git-ignored). Cost: a launcher command/shortcut instead of a
double-click, and a separate settings profile. Nothing is written to `%APPDATA%\Code` or
`~/.ssh`.

---

## File layout

```
ai-remote.code-workspace      committed   the VS Code entry point (alias-based, no IP)
.vscode/extensions.json       committed   recommends the official Remote-SSH extension
config/ssh_config.example     committed   the only template: stanza you fill in once
scripts/check-no-secrets.sh   committed   CI guard: no keys, tokens or literal IPs
docs/SECURITY.md              committed   threat model and the "what stays local" contract
config/ssh_config             GIT-IGNORED real stanza: address + absolute key path
config/id_ed25519             GIT-IGNORED the private key itself — read in place by ssh
config/known_hosts            GIT-IGNORED host keys learned on first connect
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
       UserKnownHostsFile "C:/Users/you/ai-remote/config/known_hosts"
       IdentitiesOnly yes
       PreferredAuthentications publickey
       StrictHostKeyChecking accept-new
   ```

2. `ai-remote.code-workspace` opens
   `vscode-remote://ssh-remote+nexus-ai/opt/workspace/ai`. Remote-SSH runs your normal
   OpenSSH client, which passes only the **alias** to `ssh`, so every connection detail comes
   from the project's `config/ssh_config`. The committed file therefore holds no address and
   no key.

3. VS Code installs **VS Code Server** on the remote on first connect; the folder you see is
   `/opt/workspace/ai` on the remote filesystem.

Why the alias and not a literal address: the repo is public, so `user@<ip>:22` in git would
advertise an SSH endpoint. The alias keeps the address local, and it survives an IP change.

---

## Known constraints of the reference host

Measured on the machine this repo was designed for (2 vCPU / 3.8 GB RAM / 38 GB disk,
Ubuntu):

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
