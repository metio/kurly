#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Prepares the build context for a workload's SINGLE-LAYER source image. The
# workload's jsonnet source is laid out as a vendor tree
# (github.com/metio/kurly/workloads/<name>/...) — the SAME shape and build as
# the kurly library and JOI images: a `FROM scratch` image with one COPY, so its
# single layer extracts to those files and JaaS renders them. This is why the
# artifact is NOT an oras-pushed tarball: that layer would carry an image.title
# annotation and be consumed as a file named source.tar.gz, not extracted to a
# tree, so JaaS would find no source to import. Single-layer also lets Flux's
# source-controller consume it with no layerSelector.
#
# The per-stage `version` constant is rewritten from 'dev' to the release
# version, so the rendered objects carry app.kubernetes.io/version.
#
# Emits <outdir>/Containerfile and <outdir>/github.com/... for `docker build`.
# Usage: build-workload-artifact.sh <workload-dir> <version> <outdir>
set -euo pipefail

cd "$(dirname "$0")/.."

workload_dir="$1"
version="$2"
outdir="$3"
name="$(basename "$workload_dir")"

dest="$outdir/github.com/metio/kurly/workloads/$name"
mkdir -p "$dest"

# Copy the jsonnet source (the composable stage apps plus the migration ladder),
# rewriting the version constant. Non-source files (README) stay out.
shopt -s nullglob
for source in "$workload_dir"/*.libsonnet "$workload_dir"/*.jsonnet; do
  sed "s/^local version = 'dev';/local version = '$version';/" "$source" \
    > "$dest/$(basename "$source")"
done
shopt -u nullglob

cat > "$outdir/Containerfile" <<'CONTAINERFILE'
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD
# A single-layer vendor-tree image of the workload's jsonnet source, the same
# shape as the kurly library image, consumed by JaaS via a Flux OCIRepository.
FROM scratch
COPY github.com /github.com
CONTAINERFILE

echo "prepared '$name' source build context at version '$version' ($(find "$dest" -type f | wc -l) files)"
