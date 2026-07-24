#!/usr/bin/env bash
# Run once in a shell where GIT_USER and GIT_PWD are already exported.
set -euo pipefail
AUTH_FILE="${GIT_AUTH_FILE:-$HOME/.git-auth.env}"
if [[ -z "${GIT_USER:-}" || -z "${GIT_PWD:-}" ]]; then
  echo "Export GIT_USER and GIT_PWD in this shell first." >&2
  exit 1
fi
umask 077
{
  printf 'export GIT_USER=%q\n' "$GIT_USER"
  printf 'export GIT_PWD=%q\n' "$GIT_PWD"
} >"$AUTH_FILE"
echo "Wrote ${AUTH_FILE} (chmod 600). Agents and login shells will load it via ~/.bashrc / ~/.profile."
