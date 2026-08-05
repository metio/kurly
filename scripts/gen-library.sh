# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Emits everything the catalogue holds that is NOT about one workload: the closed
# vocabularies, the library's own API model, and the list of software this
# catalogue refuses to carry.
#
#   gen-library [outfile]        (outfile defaults to stdout)
#
# WHY IT EXISTS. Per-workload metadata rides on each workload's own artifact, so
# it cannot drift from the thing it describes. That covers 867KB of the 932KB
# catalogue and leaves 64KB that has nowhere to ride:
#
#   requiresKinds, excludedReasons   closed vocabularies SHARED across workloads.
#                                    Restating them per workload is how they drift
#                                    apart, and a consumer validating against one
#                                    workload's copy would be validating against a
#                                    guess.
#
#   excluded                         the software kurly will NOT carry, and why.
#                                    This is the hard one: a rejected workload has
#                                    NO ARTIFACT, so there is nothing to attach it
#                                    to. It is information defined by absence —
#                                    and it is exactly what stops a consumer
#                                    listing something it should not.
#
#   features, kinds, expose,         the library's own API model, which the docs
#   security, network, mesh,         site's assembler renders. A property of the
#   backup, helpers, migrations      library, not of any workload.
#
#   bsiPolicies                      the policy definitions each stage's `bsi`
#                                    verdict refers to by id.
#
# It is deliberately NOT "catalog.json without the big field". The rule is one
# sentence: a fact about ONE workload rides on that workload's artifact; a fact
# about the catalogue or the library is published here. `workloads` is the only
# key that fails that test today, which is why stripping it is the whole of the
# transformation — but the rule is what decides where a NEW key goes, not the
# precedent of this line.
#
# ONE KEY HERE ALREADY BREAKS THAT RULE, and it is written down rather than left
# to be noticed: `consent` is a map keyed by workload id, so it is per-workload
# data sitting in the shared document. It ships here today because it is EMPTY —
# no maintainer has been asked yet — and moving an empty map is a schema change
# for no benefit. The moment one workload carries a consent record, it belongs in
# that workload's own entry, where it cannot be read for a workload the consumer
# did not pull. Until then this is the cheapest correct thing, not the right one.
#
# The envelope mirrors gen-workload-metadata's: `envelopeVersion` is this
# wrapper's, `schemaVersion` keeps exactly the meaning it has in catalog.json, so
# a consumer reading either document reads the same version under the same key.
set -uo pipefail

out="${1:-}"

[ -f .build/catalog.json ] || {
  echo "::error::.build/catalog.json is not there — run gen-catalog first" >&2
  exit 1
}

# `library` and `k8sLibsonnet` are the artifact stamp stamp-catalog writes at
# release time — which artifacts these facts were RENDERED FROM. They are
# provenance about the document, not part of the model it publishes, so they are
# hoisted into the envelope rather than left to nest as `.library.library`. Absent
# before a release stamps them, which is why the key only appears when they exist.
doc="$(jq -e '
  {
    envelopeVersion: 1,
    schemaVersion: .schemaVersion,
    library: (del(.workloads) | del(.schemaVersion) | del(.library) | del(.k8sLibsonnet)),
  }
  + (if .library or .k8sLibsonnet
     then { renderedFrom: ({ library: .library, k8sLibsonnet: .k8sLibsonnet } | with_entries(select(.value != null))) }
     else {} end)
' .build/catalog.json)" || {
  echo "::error::could not project the library document out of .build/catalog.json" >&2
  exit 1
}

# A consumer validating against an empty vocabulary would accept anything, so an
# empty one is a bug rather than a state — say so here rather than publishing it.
printf '%s' "$doc" | jq -e '
  (.library.excludedReasons | length > 0)
  and (.library.requiresKinds | length > 0)
' >/dev/null || {
  echo "::error::the library document carries an empty closed vocabulary" >&2
  exit 1
}

if [ -n "$out" ]; then
  printf '%s\n' "$doc" >"$out"
  echo "wrote $(wc -c <"$out") bytes to ${out}"
else
  printf '%s\n' "$doc"
fi
