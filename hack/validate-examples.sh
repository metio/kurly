#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Renders every example and validates each contained manifest against the
# upstream Kubernetes JSON schemas via kubeconform. Examples render to a
# `kind: List`, so the items are split into one file per manifest first —
# kubeconform validates plain manifests, not List wrappers.
set -euo pipefail

cd "$(dirname "$0")/.."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for example in examples/*.jsonnet; do
  name="$(basename "$example" .jsonnet)"
  echo "rendering $example"
  jsonnet -J vendor "$example" \
    | jq -c '.items[]' \
    | split --lines=1 --additional-suffix=.json - "$workdir/$name-"
done

# Gateway API kinds are CRDs, validated against the community CRD schema
# catalog. -ignore-missing-schemas covers kinds the catalog has not picked up
# yet; the summary line reports how many manifests were skipped, so a silent
# gap stays visible.
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  "$workdir"/*.json
