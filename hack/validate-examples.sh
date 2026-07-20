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
#
# All sources render in ONE jsonnet process: a single invocation imports
# k8s-libsonnet once and shares it across every render, rather than paying the
# parse per source. A per-source loop paid ~60ms of interpreter startup and
# library re-parse EVERY render, so the render cost grew with the workload count;
# batching removes that, and only the (already parallel) kubeconform pass scales.
set -euo pipefail
# An unmatched glob must expand to nothing rather than to its own pattern: no
# workload ships a migration ladder today, and the literal pattern would reach
# jsonnet as a filename and fail the gate.
shopt -s nullglob

cd "$(dirname "$0")/.."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

sources=(examples/*.jsonnet workloads/*/*.libsonnet workloads/*/migrations.jsonnet)

# A filesystem-safe key for a source: its path with slashes turned to dashes and
# the extension dropped (workloads/tik/backend.libsonnet -> workloads-tik-backend).
keyof() { local k="${1//\//-}"; printf '%s' "${k%.*}"; }

# The jsonnet expression that renders one source to its manifests: a stage app is
# wrapped in kurly.list the way a consumer's JsonnetSnippet does; an example or a
# migration ladder is imported as-is.
exprof() {
  case "$1" in
    workloads/*/*.libsonnet) printf "(import 'github.com/metio/kurly/main.libsonnet').list((import '%s')())" "$1" ;;
    *) printf "(import '%s')" "$1" ;;
  esac
}

# One program: { "<key>": <render>, ... } — evaluated by a single jsonnet process.
# Passed with -e (not a file) so its relative imports resolve against the repo
# root, exactly as the per-source `-e` renders did.
program="{"
for src in "${sources[@]}"; do
  program+=$(printf '"%s": %s,' "$(keyof "$src")" "$(exprof "$src")")
done
program+="}"

all="$workdir/all.json"
if ! jsonnet -J vendor -e "$program" >"$all" 2>"$workdir/err"; then
  # A single bad source fails the whole batch. jsonnet's error already names the
  # offending file, but re-render per source so the gate attributes it plainly.
  cat "$workdir/err" >&2
  for src in "${sources[@]}"; do
    jsonnet -J vendor -e "$(exprof "$src")" >/dev/null 2>&1 \
      || { echo "::error::$src failed to render"; exit 1; }
  done
  echo "::error::batched render failed (see above)"; exit 1
fi
echo "rendered ${#sources[@]} sources in one pass"

# Sort the sources by shape and split, in three whole-blob jq passes rather than
# one jq per source (which cost ~7s of process startup at this scale). A source
# renders to a `kind: List` (Kubernetes manifests), a plain array (a migration
# ladder, checked structurally), or neither (a bug).
mandir="$workdir/manifests"
mkdir -p "$mandir"

# Anything that is neither a List nor an array is a bug — name every offender.
bad="$(jq -r 'to_entries[] | select((.value | type) != "array" and .value.kind != "List") | .key' "$all")"
[ -z "$bad" ] || { echo "::error::did not render to a kind: List or a migration ladder:"; printf '  %s\n' $bad >&2; exit 1; }

# Every ladder must be non-empty with each entry named and version-bounded.
badladder="$(jq -r 'to_entries[] | select((.value | type) == "array") | select((.value | length) == 0 or (.value | all(.[]; has("name") and has("to"))) == false) | .key' "$all")"
[ -z "$badladder" ] || { echo "::error::not a valid migration ladder (non-empty, every entry named with a version boundary):"; printf '  %s\n' $badladder >&2; exit 1; }
ladders="$(jq -r '[.[] | select(type == "array")] | length' "$all")"
[ "$ladders" = "0" ] || echo "checked $ladders migration ladder(s) structurally (no Kubernetes schemas apply)"

# Split every List's items into one file per manifest — one jq pass for all sources.
jq -c '.[] | select(.kind == "List") | .items[]' "$all" \
  | split --lines=1 --additional-suffix=.json - "$mandir/manifest-"

# A persistent schema cache so the remote CRD schemas (Gateway API and the
# operator CRDs) are fetched once and reused, rather than re-downloaded every run
# — this, not the render, is what dominates repeated local runs. CI restores it
# from the same actions cache as the nix store.
cache="${KUBECONFORM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform}"
mkdir -p "$cache"

# Gateway API kinds are CRDs, validated against the CustomResourceDefinition/catalog schema
# catalog. -ignore-missing-schemas covers kinds the catalog has not picked up
# yet; the summary line reports how many manifests were skipped, so a silent
# gap stays visible.
#
# -skip lists kinds whose catalogued schema is DEFECTIVE (not merely missing).
# InnoDBCluster (mysql.oracle.com) models metadata as a closed object without the
# standard labels/annotations, so it rejects the kurly ownership labels every other
# manifest carries — a schema bug, not a manifest one (CNPG's Cluster schema has no
# such flaw). Skipping validates nothing for that kind rather than failing on a
# wrong schema.
kubeconform -strict -summary \
  -cache "$cache" \
  -n "$(nproc)" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/CustomResourceDefinition/catalog/main/schema/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  -skip InnoDBCluster \
  "$mandir"/*.json
