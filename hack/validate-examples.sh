#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Renders every example and workload and validates each contained manifest
# against the upstream Kubernetes JSON schemas via kubeconform. Sources render
# to one of three shapes:
#   - an example is a `kind: List` (rendered directly);
#   - a workload STAGE is a `*.libsonnet` composable app (a function returning a
#     kurly app) — rendered with its defaults and wrapped in kurly.list, the way
#     a consumer deploys it;
#   - a workload migration ladder is a plain array (not Kubernetes manifests,
#     checked structurally instead).
# List items are split into one file per manifest because kubeconform validates
# plain manifests, not List wrappers.
set -euo pipefail

cd "$(dirname "$0")/.."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Render a source to a kind:List (example or stage app) or an array (ladder).
render() {
  local src="$1"
  case "$src" in
    workloads/*/migrations.jsonnet)
      jsonnet -J vendor "$src" ;;
    workloads/*/*.libsonnet)
      # A composable stage app: render it with defaults and wrap it in a List,
      # exactly as a consumer's JsonnetSnippet does.
      jsonnet -J vendor -e "(import 'github.com/metio/kurly/main.libsonnet').list((import '$src')())" ;;
    *)
      jsonnet -J vendor "$src" ;;
  esac
}

for example in examples/*.jsonnet workloads/*/*.libsonnet workloads/*/migrations.jsonnet; do
  name="${example//\//-}"
  name="${name%.*}"
  echo "rendering $example"
  rendered="$workdir/$name.rendered"
  render "$example" > "$rendered"
  shape="$(jq -r 'if type == "array" then "ladder" elif .kind == "List" then "list" else "other" end' "$rendered")"
  case "$shape" in
    list)
      jq -c '.items[]' "$rendered" \
        | split --lines=1 --additional-suffix=.json - "$workdir/$name-"
      ;;
    ladder)
      jq -e 'length > 0 and all(.[]; has("name") and has("to"))' "$rendered" >/dev/null \
        || { echo "::error::$example is not a valid migration ladder (non-empty, every entry named with a version boundary)"; exit 1; }
      echo "checked $example structurally ($(jq -r 'length' "$rendered") migrations, no Kubernetes schemas apply)"
      ;;
    other)
      echo "::error::$example did not render to a kind: List or a migration ladder"; exit 1
      ;;
  esac
  rm "$rendered"
done

# Gateway API kinds are CRDs, validated against  the CustomResourceDefinition/catalog schema
# catalog. -ignore-missing-schemas covers kinds the catalog has not picked up
# yet; the summary line reports how many manifests were skipped, so a silent
# gap stays visible.
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/CustomResourceDefinition/catalog/main/schema/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  "$workdir"/*.json
