# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Run every gate the PR pipeline runs, in one shot, for a local pre-push check.
# CI runs these as separate parallel jobs for granular failure attribution; this
# runs them concurrently in one shell for the same wall-clock (~the slowest gate)
# instead of the sum. Keep the gate list in step with verify.yml's jobs.
set -uo pipefail

# Vendor k8s-libsonnet and the canonical-path symlink ONCE up front, so the gates
# that need it can run in parallel without racing on vendor/ — each skips its own
# `jb install` when KURLY_VENDORED=1.
jb install
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly
export KURLY_VENDORED=1

# Each gate runs in the background with its output captured, so a failure can be
# reported with its own log rather than interleaved with the others'.
logdir="$(mktemp -d)"
trap 'rm -rf "$logdir"' EXIT
gates=(
  "check-fmt"
  "check-catalog"
  "check-tests"
  "check-examples"
  "check-coverage"
  "check-security"
  "reuse lint"
  "yamllint ."
  "actionlint"
  "markdownlint-cli2 '**/*.md' '#vendor' '#docs/themes'"
  "typos"
)
pids=()
for i in "${!gates[@]}"; do
  bash -c "${gates[$i]}" >"$logdir/$i.log" 2>&1 &
  pids+=("$!")
done

fail=0
for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then
    fail=1
    echo "::error::gate failed: ${gates[$i]}" >&2
    sed 's/^/  | /' "$logdir/$i.log" >&2
  fi
done

if [ "$fail" != "0" ]; then
  echo "one or more gates failed (see above)" >&2
  exit 1
fi
echo "all gates passed"
