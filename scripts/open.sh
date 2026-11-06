#!/usr/bin/env bash
# Open the AI repo on the remote machine in VS Code, through the OFFICIAL
# "Remote - SSH" extension (ms-vscode-remote.remote-ssh).
#
# Requires: scripts/setup.sh already run (so the "nexus-ai" alias resolves),
#           VS Code installed, and the `code` CLI on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALIAS="nexus-ai"
[ -f "$ROOT/config/host.env" ] && ALIAS="$(. "$ROOT/config/host.env" && echo "${NEXUS_ALIAS:-nexus-ai}")"

command -v code >/dev/null 2>&1 || {
  echo "ERROR: the 'code' CLI is not on PATH (VS Code -> Command Palette -> 'Shell Command: Install code command in PATH')" >&2
  exit 1
}

if ! code --list-extensions 2>/dev/null | grep -qix 'ms-vscode-remote.remote-ssh'; then
  echo "==> installing Remote - SSH extension"
  code --install-extension ms-vscode-remote.remote-ssh --force
fi

echo "==> opening vscode-remote://ssh-remote+$ALIAS/opt/workspace/ai"
exec code --folder-uri "vscode-remote://ssh-remote+$ALIAS/opt/workspace/ai"
