# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Renders the Jsonnet deploy examples embedded in workload READMEs and validates
# every manifest they produce with kubeconform — the same discipline
# check-examples applies to examples/ and workloads/, extended to the code a
# consumer actually copies out of a README. A README example that no longer
# renders (a renamed feature, a wrong parameter) or renders to a malformed object
# (a workload bag passed where a manifest set is meant, which yields an item with
# no kind) fails here rather than shipping as a broken instruction.
set -euo pipefail
shopt -s nullglob

# The k8s-libsonnet dependency floats at upstream HEAD; vendor it fresh, and
# resolve kurly's own canonical import path locally through the vendor tree, the
# same setup as check-examples.
[ "${KURLY_VENDORED:-}" = "1" ] || jb install
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
snippets="$workdir/snippets"
mkdir -p "$snippets"

# Which READMEs to scan: every workload by default, or just the changed ones when
# KURLY_WORKLOADS narrows an incremental run — mapping each changed stage path to
# its workload README (deduplicated).
if [ -n "${KURLY_WORKLOADS:-}" ]; then
  mapfile -t readmes < <(printf '%s\n' "$KURLY_WORKLOADS" | sed -E 's#(workloads/[^/]+)/.*#\1/README.md#' | sort -u)
else
  readmes=(workloads/*/README.md)
fi

count="$(python3 hack/extract-readme-examples.py "$snippets" "${readmes[@]}")"
examples=("$snippets"/*.jsonnet)
if [ "${#examples[@]}" = "0" ]; then
  echo "no README examples to render"
  exit 0
fi
echo "extracted $count README example(s)"

# Render every extracted example in ONE jsonnet process (k8s-libsonnet parsed
# once), keyed by name. The extracted files search the vendor tree for kurly's
# canonical path and their own directory for nothing else, so -J covers both.
program="{"
for ex in "${examples[@]}"; do
  key="$(basename "${ex%.jsonnet}")"
  program+=$(printf '"%s": (import "%s"),' "$key" "$ex")
done
program+="}"

all="$workdir/all.json"
if ! jsonnet -J vendor -e "$program" >"$all" 2>"$workdir/err"; then
  # A single bad example fails the batch; re-render per example to attribute it.
  cat "$workdir/err" >&2
  for ex in "${examples[@]}"; do
    jsonnet -J vendor "$ex" >/dev/null 2>&1 \
      || { echo "::error::README example $(basename "$ex") failed to render"; exit 1; }
  done
  echo "::error::batched README-example render failed (see above)"; exit 1
fi

# Every example must render to a kind: List (the shape kurly.list produces) — a
# non-List is a broken example.
bad="$(jq -r 'to_entries[] | select(.value.kind != "List") | .key' "$all")"
[ -z "$bad" ] || { echo "::error::README example(s) did not render to a kind: List:" >&2; echo "$bad" >&2; exit 1; }

# Split every List's items into one file per manifest — kubeconform validates
# plain manifests, not List wrappers. A -strict run rejects an item with no kind,
# which is exactly what a workload bag passed to kurly.list in place of a manifest
# set would produce.
mandir="$workdir/manifests"
mkdir -p "$mandir"
jq -c '.[] | .items[]' "$all" \
  | split --lines=1 --additional-suffix=.json - "$mandir/manifest-"

# The shared schema cache and the same schema locations / skips as
# check-examples: core kinds against the upstream schemas, CRD kinds against the
# community catalog, InnoDBCluster skipped for its defective catalog schema.
cache="${KUBECONFORM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform}"
mkdir -p "$cache"
kubeconform -strict -summary \
  -cache "$cache" \
  -n "${KURLY_JOBS:-$(nproc)}" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/CustomResourceDefinition/catalog/main/schema/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  -skip InnoDBCluster \
  "$mandir"/*.json
