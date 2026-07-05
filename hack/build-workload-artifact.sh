#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Builds the layer set of a workload OCI image: one gzipped tarball per
# rollout stage (rendered from a stages file — a map of stage name -> kind:
# List) plus one for the migration ladder. Each layer carries its own media
# type, so a Flux OCIRepository selects exactly one stage via
# spec.layerSelector.mediaType:
#
#   stage layer:      application/vnd.metio.stage.<stage>.tar+gzip
#   migrations layer: application/vnd.metio.migrations.tar+gzip
#
# Tarballs are deterministic (sorted entries, zero timestamps, numeric owner
# 0:0, gzip -n), so rebuilding unchanged sources yields identical layer
# digests. The emitted <outdir>/layers.txt lists `file:mediaType` pairs in
# stable order (stages sorted, migrations last), ready to splat into
# `oras push`.
#
# Usage: build-workload-artifact.sh <stages.jsonnet> <migrations.jsonnet> <outdir>
set -euo pipefail

cd "$(dirname "$0")/.."

stages_file="$1"
migrations_file="$2"
outdir="$3"
mkdir -p "$outdir"

layers="$outdir/layers.txt"
: > "$layers"

pack() {
  local dir="$1" tarball="$2"
  tar --create --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --directory "$dir" . | gzip -n > "$tarball"
}

rendered="$outdir/stages.json"
jsonnet -J vendor "$stages_file" > "$rendered"

for stage in $(jq -r 'keys_unsorted | sort | .[]' "$rendered"); do
  stagedir="$outdir/$stage"
  mkdir -p "$stagedir"
  jq -c --arg stage "$stage" '.[$stage].items[]' "$rendered" \
    | split --lines=1 --additional-suffix=.json - "$stagedir/manifest-"
  pack "$stagedir" "$outdir/$stage.tar.gz"
  echo "$stage.tar.gz:application/vnd.metio.stage.$stage.tar+gzip" >> "$layers"
  echo "packed stage '$stage' ($(jq -r --arg stage "$stage" '.[$stage].items | length' "$rendered") manifests)"
done

# The ladder is JSON on the wire; the .yaml name keeps it valid for YAML-only
# loaders since every JSON document is a YAML document.
migrationsdir="$outdir/migrations"
mkdir -p "$migrationsdir"
jsonnet -J vendor "$migrations_file" > "$migrationsdir/migrations.yaml"
pack "$migrationsdir" "$outdir/migrations.tar.gz"
echo "migrations.tar.gz:application/vnd.metio.migrations.tar+gzip" >> "$layers"
echo "packed migration ladder ($(jq -r 'length' "$migrationsdir/migrations.yaml") migrations)"
