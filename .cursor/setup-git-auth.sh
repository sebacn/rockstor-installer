#!/usr/bin/env bash
# Configure git to reuse GitHub HTTPS credentials from the environment or ~/.git-auth.env
set -euo pipefail
AUTH_FILE="${GIT_AUTH_FILE:-$HOME/.git-auth.env}"
if [[ -f "$AUTH_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$AUTH_FILE"
  set +a
fi
if [[ -z "${GIT_USER:-}" || -z "${GIT_PWD:-}" ]]; then
  echo "Missing GIT_USER or GIT_PWD." >&2
  echo "Export them in this shell, or create ${AUTH_FILE} (chmod 600) with:" >&2
  echo '  export GIT_USER="your-github-username"' >&2
  echo '  export GIT_PWD="your-personal-access-token"' >&2
  exit 1
fi
umask 077
git config --global credential.helper store
printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
  "$GIT_USER" "$GIT_PWD" | git credential approve
git -C "${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}" ls-remote origin HEAD >/dev/null
echo "GitHub HTTPS auth OK (credential.helper=store)."
