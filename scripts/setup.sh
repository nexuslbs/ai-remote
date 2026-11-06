#!/usr/bin/env bash
# One-command installer: render the SSH alias that ai-remote.code-workspace uses.
#
# It reads the NON-VERSIONED files in config/ and points ssh straight AT the private
# key kept in config/ - the key is used in place, never copied into ~/.ssh:
#
#   config/host.env     machine address (IP/DNS), user, port, alias     [git-ignored]
#   config/id_ed25519   the PRIVATE key itself, read directly           [git-ignored]
#   config/key.path     OPTIONAL override: absolute path of another key [git-ignored]
#
# Result: ~/.ssh/config.d/<alias> (IdentityFile -> the config/ path) plus an
#         `Include` line at the top of ~/.ssh/config.
#
# Windows: run this from Git-Bash ("Git Bash Here" in the repo folder), NOT from WSL
# and not from cmd/PowerShell. VS Code's Remote-SSH uses the Windows OpenSSH client,
# whose config is %USERPROFILE%\.ssh\config - Git-Bash's $HOME is exactly that folder.
#
# Usage: ./scripts/setup.sh [--print] [--no-test] [--force]
#   --print    show the fragment that would be written, change nothing
#   --no-test  skip the live connection attempt at the end
#   --force    proceed even when WSL is detected
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_ENV="$ROOT/config/host.env"
KEY_PTR="$ROOT/config/key.path"
SSH_DIR="$HOME/.ssh"
CONF_D="$SSH_DIR/config.d"

PRINT_ONLY=0
RUN_TEST=1
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --print)   PRINT_ONLY=1 ;;
    --no-test) RUN_TEST=0 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

die()  { printf '\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*" >&2; }

# ---------- 0. platform ----------
IS_WINDOWS=0
case "${OSTYPE:-$(uname -s)}" in msys*|cygwin*|win32*) IS_WINDOWS=1 ;; esac
IS_WSL=0
if [ "$IS_WINDOWS" = 0 ] && [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
fi
if [ "$IS_WSL" = 1 ] && [ "$FORCE" = 0 ]; then
  die "WSL detected. VS Code on Windows reads %USERPROFILE%\\.ssh\\config through the Windows OpenSSH client, so an alias written here would never be used. Open the repo in Git-Bash (right-click -> 'Git Bash Here') and run ./scripts/setup.sh there; use --force only if you really want a Linux-side alias."
fi

# Path form that the ssh client VS Code will spawn can understand.
native_path() {
  if [ "$IS_WINDOWS" = 1 ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -m -- "$1"
  else
    printf '%s\n' "$1"
  fi
}

# ---------- 1. address (config/host.env) ----------
if [ ! -f "$HOST_ENV" ]; then
  cp "$ROOT/config/host.env.example" "$HOST_ENV"
  die "created $HOST_ENV - edit it with your machine IP, then re-run."
fi
# shellcheck disable=SC1090
set -a; . "$HOST_ENV"; set +a

NEXUS_SSH_HOST="${NEXUS_SSH_HOST:-}"
NEXUS_SSH_USER="${NEXUS_SSH_USER:-root}"
NEXUS_SSH_PORT="${NEXUS_SSH_PORT:-22}"
NEXUS_ALIAS="${NEXUS_ALIAS:-nexus-ai}"
NEXUS_REMOTE_PATH="${NEXUS_REMOTE_PATH:-/opt/workspace/ai}"

[ -n "$NEXUS_SSH_HOST" ] || die "NEXUS_SSH_HOST is empty in $HOST_ENV"
case "$NEXUS_SSH_HOST" in
  203.0.113.*|example.*|CHANGEME*) die "NEXUS_SSH_HOST still has the placeholder value in $HOST_ENV" ;;
esac

# ---------- 2. the key, read from config/ ----------
KEY_PATH=""
KEY_SOURCE=""
if [ -f "$KEY_PTR" ]; then
  KEY_PATH="$(awk '!/^[[:space:]]*#/ && NF {print $1; exit}' "$KEY_PTR" | tr -d '\r')"
  KEY_PATH="${KEY_PATH%"${KEY_PATH##*[![:space:]]}"}"
  [ -n "$KEY_PATH" ] || die "$KEY_PTR contains no path"
  case "$KEY_PATH" in "~/"*) KEY_PATH="$HOME/${KEY_PATH#\~/}" ;; esac
  KEY_SOURCE="$KEY_PTR"
else
  # Default: the key sits directly in config/ - that is the whole point.
  for cand in "$ROOT/config/id_ed25519" "$ROOT/config/id_ecdsa" "$ROOT/config/id_rsa"; do
    if [ -f "$cand" ]; then KEY_PATH="$cand"; KEY_SOURCE="config/$(basename "$cand")"; break; fi
  done
fi

if [ -z "$KEY_PATH" ]; then
  cat >&2 <<EOF
$(printf '\033[31mERROR\033[0m') no private key found in config/.

Put YOUR existing private key there (it stays git-ignored, ssh uses it in place):

  Git-Bash / macOS / Linux :  cp ~/.ssh/id_ed25519            config/id_ed25519
  Windows (cmd/PowerShell) :  copy "%USERPROFILE%\\.ssh\\id_ed25519" "config\\id_ed25519"

No key yet? Create a dedicated pair and authorise it on the remote:

  ssh-keygen -t ed25519 -a 100 -C "vscode@\$(hostname)" -f config/id_ed25519
  ssh-copy-id -i config/id_ed25519.pub ${NEXUS_SSH_USER}@<machine>

Then re-run ./scripts/setup.sh
EOF
  exit 1
fi

[ -f "$KEY_PATH" ] || die "private key not found: $KEY_PATH (from $KEY_SOURCE)"
KEY_HEAD="$(head -c 200 "$KEY_PATH" 2>/dev/null || true)"
case "$KEY_HEAD" in
  *"PRIVATE KEY"*) ;;
  *) die "$KEY_PATH is not an OpenSSH/PEM private key" ;;
esac

# Refuse a key that git tracks - this repo is public.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$ROOT" ls-files --error-unmatch "$KEY_PATH" >/dev/null 2>&1; then
    die "$KEY_PATH IS TRACKED BY GIT - refusing to continue. Run: git -C \"$ROOT\" rm --cached \"$KEY_PATH\" && git commit -m 'untrack key'"
  fi
fi

# Permissions: OpenSSH refuses keys that other users can read.
# Skipped in --print mode (it must not change anything on disk).
if [ "$PRINT_ONLY" = 1 ]; then
  :
elif [ "$IS_WINDOWS" = 1 ]; then
  if command -v icacls >/dev/null 2>&1; then
    WIN_KEY="$(native_path "$KEY_PATH")"
    ACL_OUT="$(icacls "$WIN_KEY" 2>/dev/null || true)"
    case "$ACL_OUT" in
      *'(I)'*)
        say "restricting the Windows ACL of the key to $(whoami)"
        icacls "$WIN_KEY" /inheritance:r /grant:r "$(whoami):F" >/dev/null 2>&1 \
          || warn "icacls failed - Windows OpenSSH may reject the key as 'too open'" ;;
      *)
        say "Windows ACL of the key is already restricted" ;;
    esac
  else
    warn "icacls not found - if ssh complains the key is 'too open', right-click the file -> Properties -> Security -> remove inherited permissions and keep only your user"
  fi
else
  PERMS="$(stat -c '%a' "$KEY_PATH" 2>/dev/null || stat -f '%Lp' "$KEY_PATH" 2>/dev/null || echo '')"
  case "$PERMS" in
    600|400) ;;
    "")      warn "could not read the permissions of $KEY_PATH" ;;
    *)       say "tightening key permissions ($PERMS -> 600)"; chmod 600 "$KEY_PATH" ;;
  esac
fi
say "key: $KEY_PATH  (source: $KEY_SOURCE, used in place - not copied)"

# ---------- 3. render the ssh config fragment ----------
KEY_FOR_SSH="$(native_path "$KEY_PATH")"
FRAG="$CONF_D/$NEXUS_ALIAS"
if [ "$PRINT_ONLY" = 0 ]; then
  mkdir -p "$CONF_D"
  chmod 700 "$SSH_DIR" "$CONF_D" 2>/dev/null || true
fi
BLOCK="$(cat <<EOF
# Managed by nexuslbs/ai-remote scripts/setup.sh - do not edit by hand.
# Source of truth: config/host.env + the key in config/ (both git-ignored).
Host $NEXUS_ALIAS
    HostName $NEXUS_SSH_HOST
    User $NEXUS_SSH_USER
    Port $NEXUS_SSH_PORT
    IdentityFile "$KEY_FOR_SSH"
    IdentitiesOnly yes
    PreferredAuthentications publickey
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ForwardAgent no
    Compression no
EOF
)"

if [ "$PRINT_ONLY" = 1 ]; then
  say "would write $FRAG:"
  printf '%s\n' "$BLOCK"
  say "would ensure '$SSH_DIR/config' contains: Include $(native_path "$FRAG")"
  exit 0
fi
printf '%s\n' "$BLOCK" > "$FRAG"
chmod 600 "$FRAG"
say "wrote $FRAG"

# ---------- 4. make sure ~/.ssh/config includes it ----------
touch "$SSH_DIR/config"; chmod 600 "$SSH_DIR/config"
INCLUDE_LINE="Include $(native_path "$FRAG")"
if ! grep -Fxq "$INCLUDE_LINE" "$SSH_DIR/config"; then
  # an Include must come before any Host block that could shadow it
  cp "$SSH_DIR/config" "$SSH_DIR/config.bak.$$" 2>/dev/null || true
  printf '%s\n' "$INCLUDE_LINE" | cat - "$SSH_DIR/config" > "$SSH_DIR/config.tmp.$$"
  mv "$SSH_DIR/config.tmp.$$" "$SSH_DIR/config"
  chmod 600 "$SSH_DIR/config"
  say "added '$INCLUDE_LINE' at the top of $SSH_DIR/config (backup: config.bak.$$)"
else
  say "$SSH_DIR/config already includes $FRAG"
fi

# ---------- 5. verify ----------
if command -v ssh >/dev/null 2>&1; then
  say "resolved config for '$NEXUS_ALIAS':"
  ssh -G "$NEXUS_ALIAS" 2>/dev/null | awk '$1=="hostname"||$1=="user"||$1=="port"||$1=="identityfile"{print "    "$0}' || true
else
  warn "no ssh client on PATH - cannot resolve/verify the alias"
fi

if [ "$RUN_TEST" = 1 ]; then
  say "testing the connection (BatchMode, public key only)..."
  if ssh -o BatchMode=yes -o ConnectTimeout=15 "$NEXUS_ALIAS" \
       'printf "OK %s@%s %s\n" "$USER" "$(hostname)" "$(uname -sr)"' 2>&1 | tail -3; then
    say "SSH alias '$NEXUS_ALIAS' is ready."
  else
    die "connection FAILED - check NEXUS_SSH_HOST in config/host.env and that config/$(basename "$KEY_PATH").pub is in the remote ~/.ssh/authorized_keys"
  fi
fi

say "next: ./scripts/open.sh        (or: code --folder-uri \"vscode-remote://ssh-remote+$NEXUS_ALIAS$NEXUS_REMOTE_PATH\")"
