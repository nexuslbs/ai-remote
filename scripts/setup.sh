#!/usr/bin/env bash
# Render the SSH host alias that the .code-workspace uses, from the two
# NON-VERSIONED files in config/. Nothing secret is written into this repo.
#
#   config/host.env   -> machine address (IP/DNS), user, port, alias
#   config/key.path   -> absolute path of the private key on THIS machine
#
# Result: ~/.ssh/config.d/<alias>, included from ~/.ssh/config.
# Usage: ./scripts/setup.sh [--print]   (--print only shows what it would write)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_ENV="$ROOT/config/host.env"
KEY_PTR="$ROOT/config/key.path"
SSH_DIR="$HOME/.ssh"
CONF_D="$SSH_DIR/config.d"
PRINT_ONLY=0
[ "${1:-}" = "--print" ] && PRINT_ONLY=1

die() { printf '\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

# ---------- 1. read non-versioned config ----------
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

if [ ! -f "$KEY_PTR" ]; then
  cp "$ROOT/config/key.path.example" "$KEY_PTR"
  die "created $KEY_PTR - put the absolute path of your private key in it, then re-run."
fi
KEY_PATH="$(grep -v '^[[:space:]]*#' "$KEY_PTR" | grep -v '^[[:space:]]*$' | head -1 | sed 's/[[:space:]]*$//')"
[ -n "$KEY_PATH" ] || die "$KEY_PTR contains no path"
case "$KEY_PATH" in "~/"*) KEY_PATH="$HOME/${KEY_PATH#\~/}" ;; esac

[ -f "$KEY_PATH" ] || die "private key not found: $KEY_PATH (generate one: ssh-keygen -t ed25519 -a 100 -f \"$KEY_PATH\")"
PERMS="$(stat -c '%a' "$KEY_PATH" 2>/dev/null || stat -f '%Lp' "$KEY_PATH")"
case "$PERMS" in 600|400) ;; *) say "tightening key permissions ($PERMS -> 600)"; chmod 600 "$KEY_PATH" ;; esac

# ---------- 2. render the ssh config fragment ----------
mkdir -p "$CONF_D"
chmod 700 "$SSH_DIR" "$CONF_D" 2>/dev/null || true
FRAG="$CONF_D/$NEXUS_ALIAS"
BLOCK="$(cat <<EOF
# Managed by nexuslbs/ai-remote scripts/setup.sh - do not edit by hand.
# Source of truth: config/host.env + config/key.path (both git-ignored).
Host $NEXUS_ALIAS
    HostName $NEXUS_SSH_HOST
    User $NEXUS_SSH_USER
    Port $NEXUS_SSH_PORT
    IdentityFile "$KEY_PATH"
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
  exit 0
fi
printf '%s\n' "$BLOCK" > "$FRAG"
chmod 600 "$FRAG"
say "wrote $FRAG"

# ---------- 3. make sure ~/.ssh/config includes it ----------
touch "$SSH_DIR/config"; chmod 600 "$SSH_DIR/config"
INCLUDE_LINE="Include $FRAG"
if ! grep -Fxq "$INCLUDE_LINE" "$SSH_DIR/config"; then
  # an Include must come before any Host block that could shadow it
  printf '%s\n' "$INCLUDE_LINE" | cat - "$SSH_DIR/config" > "$SSH_DIR/config.tmp.$$"
  mv "$SSH_DIR/config.tmp.$$" "$SSH_DIR/config"
  chmod 600 "$SSH_DIR/config"
  say "added '$INCLUDE_LINE' at the top of $SSH_DIR/config"
else
  say "$SSH_DIR/config already includes $FRAG"
fi

# ---------- 4. verify ----------
say "resolved config:"
ssh -G "$NEXUS_ALIAS" 2>/dev/null | awk '$1=="hostname"||$1=="user"||$1=="port"||$1=="identityfile"{print "    "$0}'

say "testing connection (BatchMode, keyword-only auth)..."
if ssh -o BatchMode=yes -o ConnectTimeout=15 "$NEXUS_ALIAS" 'printf "OK %s@%s %s\\n" "$USER" "$(hostname)" "$(uname -sr)"' 2>&1 | tail -3; then
  say "SSH alias '$NEXUS_ALIAS' is ready."
else
  say "connection FAILED - check the IP in config/host.env and that the public half of $KEY_PATH is in the remote ~/.ssh/authorized_keys"
  exit 1
fi

say "next: ./scripts/open.sh   (opens $NEXUS_REMOTE_PATH in VS Code over SSH)"
