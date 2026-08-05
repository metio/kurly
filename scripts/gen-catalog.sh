# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Renders .build/catalog.json from the annotations and every derived ledger.
#
# catalog.json is a BUILD ARTIFACT, not source. It is the repository's internal
# join of every derived fact — twenty scripts read it, from gen-smoke to the docs
# site — and it is regenerated wherever it is needed rather than committed.
#
# It used to be committed, and that is what made it a problem rather than a
# convenience. Being an aggregate of every workload, any image bump moved it, so
# every Renovate pull request rewrote the same 1.9MB file and they conflicted with
# each other. Worse, the pull-request gate regenerated and PUSHED it: that push
# authenticates with GITHUB_TOKEN, GitHub does not trigger workflows from
# GITHUB_TOKEN events, and the commit it had just pushed therefore got no CI run —
# leaving the head commit with no checks and the pull request unmergeable.
#
# So the file is generated and gitignored, and nothing commits it. What is
# committed is what it is derived FROM: the annotations, the stages, and the
# ledgers the network-bound generators write.
#
# WRITTEN THROUGH A TEMPORARY FILE, because `jsonnet > catalog.json` truncates the
# target before it knows whether the render succeeded — so one broken annotation
# would replace the catalogue with an empty file that every downstream gate then
# measures nothing against.
set -uo pipefail

out=.build/catalog.json

# .build/ is gitignored and therefore absent in a fresh checkout, so every writer
# into it creates it. `mv` into a missing directory fails after the render has
# already succeeded — the most expensive moment to discover a missing mkdir.
mkdir -p "$(dirname "$out")"

# The generator imports the library, which imports k8s-libsonnet.
[ "${KURLY_VENDORED:-}" = "1" ] || jb install >/dev/null

# The workloads section imports each stage by kurly's canonical path
# (github.com/metio/kurly/...); resolve it locally by symlinking the repo into the
# vendor tree, exactly as check-catalog and check-examples do.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if ! jsonnet -J vendor catalog/catalog.jsonnet > "$tmp"; then
  echo "::error::catalog/catalog.jsonnet does not render — ${out} left untouched" >&2
  exit 1
fi

if ! jq -e '.schemaVersion and (.workloads | length > 0)' "$tmp" >/dev/null 2>&1; then
  echo "::error::the rendered catalogue has no schemaVersion or no workloads — ${out} left untouched" >&2
  exit 1
fi

mv "$tmp" "$out"
trap - EXIT
echo "wrote ${out} ($(jq '.workloads | length' "$out") workloads, $(jq '.excluded | length' "$out") excluded)"
