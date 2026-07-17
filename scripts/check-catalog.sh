# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog gate: regenerate catalog/catalog.json from the library annotations
# and fail if the committed copy is stale. Rendering it also runs the drift
# asserts in catalog.jsonnet (a feature exported without an annotation, or an
# annotation with no matching export, fails here) — so the machine-readable API
# model the assembler reads can never silently disagree with the library.

# The generator imports the library, which imports k8s-libsonnet; vendor it.
jb install

# The workloads section imports each stage by kurly's canonical path
# (github.com/metio/kurly/...); resolve it locally by symlinking the repo into
# the vendor tree, exactly as check-examples does.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

generated="$(jsonnet -J vendor catalog/catalog.jsonnet)"

if ! diff -u catalog/catalog.json <(printf '%s\n' "$generated") >/dev/null; then
  echo "catalog/catalog.json is stale — regenerate it:" >&2
  echo "  jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json" >&2
  echo >&2
  diff -u catalog/catalog.json <(printf '%s\n' "$generated") >&2 || true
  exit 1
fi
echo "catalog is in sync with the library"

# The catalog claims to be the machine-readable model of kurly's public API — the
# Assembler builds snippets from it and the Reference site renders it — and
# catalog.jsonnet already fails when a FEATURE is exported without an annotation.
# A workload stage's PARAMETERS had no such check, and drifted: 27 of them went
# undocumented, including every knob added to cnpg-cluster for storage, placement
# and pull secrets. A parameter the catalog omits is a parameter nobody can find,
# which makes it a private API however well it works.
#
# jsonnet cannot introspect a function's parameters, so the signature is read
# from the source. That is reliable precisely because check-fmt enforces the
# layout: jsonnetfmt puts one parameter per line, indented two spaces.
echo "== every workload parameter is annotated =="
fail=0
for stage in workloads/*/*.libsonnet; do
  workload="$(basename "$(dirname "$stage")")"
  id="$(basename "$stage" .libsonnet)"

  # ORDER matters as much as membership: the Assembler and the coverage generator
  # bind these positionally, so a catalog listing the same names in a different
  # order renders every value into the wrong parameter — which schema validation
  # catches only when the types happen to disagree.
  actual="$(sed -n '/^function(/,/^)/p' "$stage" | grep -oE '^  [a-zA-Z][a-zA-Z0-9]*=' | tr -d ' =')"
  documented="$(jq -r --arg w "$workload" --arg s "$id" \
    '.workloads[] | select(.id == $w) | .stages[] | select(.id == $s) | .args[]?.name' catalog/catalog.json)"

  missing="$(comm -23 <(printf '%s\n' "$actual" | sort -u) <(printf '%s\n' "$documented" | sort -u) | tr '\n' ' ')"
  stale="$(comm -13 <(printf '%s\n' "$actual" | sort -u) <(printf '%s\n' "$documented" | sort -u) | tr '\n' ' ')"
  if [ -n "${missing// /}" ]; then
    echo "::error::${stage}: parameter(s) not annotated in catalog/annotations.libsonnet: ${missing}" >&2
    fail=1
  elif [ -n "${stale// /}" ]; then
    echo "::error::${stage}: annotated parameter(s) the function does not take: ${stale}" >&2
    fail=1
  elif [ "$actual" != "$documented" ]; then
    echo "::error::${stage}: annotated parameters are in a different order than the function declares them —" >&2
    echo "  function: $(printf '%s' "$actual" | tr '\n' ' ')" >&2
    echo "  catalog:  $(printf '%s' "$documented" | tr '\n' ' ')" >&2
    fail=1
  else
    echo "every parameter annotated, in order: $stage"
  fi
done
[ "$fail" -eq 0 ] || exit 1
