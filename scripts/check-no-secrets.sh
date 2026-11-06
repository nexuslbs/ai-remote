#!/usr/bin/env bash
# Guard: this repo must stay credential-free. Run in CI and as a pre-commit hook.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-|sk-[A-Za-z0-9]{20,}'
# A bare IPv4 is not a secret, but this repo must not publish the real host.
IP_PATTERN='(^|[^0-9.])((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])([^0-9.]|$)'

fail=0
hits="$(git grep -nEI "$PATTERNS" -- . ':!scripts/check-no-secrets.sh' ':!.github/' || true)"
if [ -n "$hits" ]; then
  echo "BLOCKED: credential-looking strings found:"; echo "$hits"; fail=1
fi

ips="$(git grep -nEI "$IP_PATTERN" -- . ':!scripts/check-no-secrets.sh' ':!.github/' 2>/dev/null \
      | grep -vE '127\.0\.0\.1|0\.0\.0\.0|255\.255\.255|203\.0\.113\.|1\.2\.3\.4|21[0-9]\.[0-9]' || true)"
if [ -n "$ips" ]; then
  echo "BLOCKED: literal IP address committed (keep it in config/host.env, git-ignored):"; echo "$ips"; fail=1
fi

for f in config/host.env config/key.path config/id_ed25519 config/id_ecdsa config/id_rsa; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "BLOCKED: $f is tracked by git but must be non-versioned"; fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "OK: no credentials, no literal IPs, local config files untracked."
exit "$fail"
