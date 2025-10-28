#!/usr/bin/env bash
set -euo pipefail

# Optional commit message argument; defaults to "update"
msg=${1:-update}

git add .
git commit -m "$msg"
git push


