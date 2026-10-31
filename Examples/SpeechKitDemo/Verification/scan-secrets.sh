#!/usr/bin/env bash
set -euo pipefail

# Run locally as well: --all includes local refs/t3/checkpoints/* when present.
# Hosted checkout cannot see private local refs, reflogs, or unreachable objects.
scanner="${GITLEAKS_BIN:-gitleaks}"
scan_log="$(mktemp)"
trap 'rm -f "$scan_log"' EXIT
if ! "$scanner" git --redact=100 --no-banner --log-level error --log-opts=--all "${1:-.}" >"$scan_log" 2>&1; then
  echo "Secret scan failed. Findings are suppressed; inspect locally with redaction enabled."
  exit 1
fi
echo "Secret scan passed for available refs."
