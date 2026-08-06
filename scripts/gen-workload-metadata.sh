#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Emits ONE workload's catalogue entry as a standalone document, for publishing
# beside that workload's own artifact.
#
# WHY PER WORKLOAD: catalog.json is 1.7MB and describes 301 workloads. A consumer
# that wants one of them downloads all of it, and — the reason this exists — the
# description and the thing it describes are two separately published objects, so
# they can disagree. catalog.json can say version N while the workload artifact is
# N+1, for as long as the two publications take to converge. Attached to the
# artifact, that state cannot be represented.
#
# The document is DERIVED from catalog.json, which is itself derived by rendering
# the stages, so nothing here is transcribed.
#
# TWO VERSIONS, because there are two things to version and they move apart.
# `envelopeVersion` is this wrapper's; `schemaVersion` is the ENTRY's, and keeps
# exactly the meaning it has in catalog.json — so an entry pulled from a referrer
# and the same entry read from the central file carry the same version under the
# same key. One number could not say which shape it promised, and the two are about
# to diverge: the envelope is at 1 while `requires` inside moves to v2.
#
#   gen-workload-metadata <workload> [outfile]      (outfile defaults to stdout)
# Run from the repository root, like every other script here: wrapped by nix,
# "$0" is a store path and its parent is not this repository.
set -euo pipefail

# .build/catalog.json is a BUILD ARTIFACT with no committed copy, so a fresh
# checkout does not have one — CI included. Producing it here rather than
# failing means a gate depends on the DATA it needs instead of on somebody
# having remembered to render it first, which is exactly the step a CI job
# forgot.
[ -f .build/catalog.json ] || gen-catalog >/dev/null

workload="${1:?usage: gen-workload-metadata <workload> [outfile]}"
out="${2:-}"

# -e makes jq exit non-zero when the selection produces null, so a workload that
# does not exist fails here rather than publishing an empty document beside a real
# image.
doc="$(jq -e --arg w "$workload" '
  (.workloads[] | select(.id == $w)) as $wl
  | {
      envelopeVersion: 1,
      schemaVersion: .schemaVersion,
      workload: $wl,
    }
' .build/catalog.json)" || {
  echo "::error::no workload '${workload}' in .build/catalog.json" >&2
  exit 1
}

if [ -n "$out" ]; then
  printf '%s\n' "$doc" >"$out"
  echo "wrote $(wc -c <"$out") bytes to ${out}"
else
  printf '%s\n' "$doc"
fi
