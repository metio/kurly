#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Renders every example and every workload and validates each contained
# manifest against the upstream Kubernetes JSON schemas via kubeconform. The
# files render to one of three shapes: a `kind: List` (single workload), a map of stage name → List
# (a staged workload — every stage's items are validated), or a plain array (a
# stageset-controller migration ladder — not Kubernetes manifests, checked
# structurally instead). List items are split into one file per manifest
# because kubeconform validates plain manifests, not List wrappers.
set -euo pipefail

cd "$(dirname "$0")/.."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for example in examples/*.jsonnet workloads/*/*.jsonnet; do
  rel="${example%.jsonnet}"
  name="${rel//\//-}"
  echo "rendering $example"
  rendered="$workdir/$name.rendered"
  jsonnet -J vendor "$example" > "$rendered"
  shape="$(jq -r 'if type == "array" then "ladder" elif .kind == "List" then "list" else "stagemap" end' "$rendered")"
  case "$shape" in
    list)
      jq -c '.items[]' "$rendered" \
        | split --lines=1 --additional-suffix=.json - "$workdir/$name-"
      ;;
    stagemap)
      for stage in $(jq -r 'keys_unsorted | sort | .[]' "$rendered"); do
        jq -e --arg stage "$stage" '.[$stage].kind == "List"' "$rendered" >/dev/null \
          || { echo "::error::$example stage '$stage' does not render a kind: List"; exit 1; }
        jq -c --arg stage "$stage" '.[$stage].items[]' "$rendered" \
          | split --lines=1 --additional-suffix=.json - "$workdir/$name-$stage-"
      done
      ;;
    ladder)
      jq -e 'length > 0 and all(.[]; has("name") and has("to"))' "$rendered" >/dev/null \
        || { echo "::error::$example is not a valid migration ladder (non-empty, every entry named with a version boundary)"; exit 1; }
      echo "checked $example structurally ($(jq -r 'length' "$rendered") migrations, no Kubernetes schemas apply)"
      ;;
  esac
  rm "$rendered"
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
