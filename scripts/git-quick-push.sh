#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[error] not inside a git repository"
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "${branch}" ]]; then
  echo "[error] failed to detect current branch"
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "[error] remote 'origin' is not configured"
  exit 1
fi

if [[ -n "${MSG:-}" ]]; then
  commit_msg="${MSG}"
else
  default_msg="docs: update on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  read -r -p "Commit message [${default_msg}]: " input_msg
  commit_msg="${input_msg:-$default_msg}"
fi

git add -A

if git diff --cached --quiet; then
  echo "[skip] no staged changes to commit"
  exit 0
fi

git commit -m "${commit_msg}"
git push origin "${branch}"

echo "[done] pushed to origin/${branch}"
