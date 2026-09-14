#!/usr/bin/env bash
# One-time developer setup: git hooks, signature verification, optional tools.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
git config gpg.ssh.allowedSignersFile .github/allowed_signers
echo "Git hooks and allowed-signers configured."
if [[ "$(git config --get commit.gpgsign || true)" != "true" ]]; then
  echo "WARNING: commit.gpgsign is not enabled. Signed commits are required on main." >&2
  echo "  See CONTRIBUTING.md for SSH signing setup." >&2
fi
command -v xcodegen >/dev/null || echo "Optional: brew install xcodegen (needed for the Xcode project)"
command -v swiftlint >/dev/null || echo "Optional: brew install swiftlint (runs in pre-commit and CI)"
command -v actionlint >/dev/null || echo "Optional: brew install actionlint (lints GitHub workflows)"
