# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog-driven coverage battery: render every feature / exposure recipe /
# security profile / kind composition that tests/coverage_gen.jsonnet builds from
# the catalog, and validate each manifest with kubeconform. Because the set is
# generated straight from catalog.json, every annotated entry is exercised on
# every kind it claims legal — a newly annotated feature is covered with no test
# authoring, and a generator gap is caught by the count assertion. check-catalog
# keeps the catalog itself honest against the library.

[ "${KURLY_VENDORED:-}" = "1" ] || jb install

# The compositions import kurly by its canonical path; resolve it via the vendor
# symlink, exactly as check-examples does.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# The expected composition count derives straight from the catalog (one per
# feature×kind, plus one per exposure recipe, security profile, and kind), so a
# generator that silently skips an entry fails here.
expected="$(jq '([.features[].kinds | length] | add) + (.expose | length) + (.security | length) + (.kinds | length) + ([.network[] | select(.standalone != true)] | length)' catalog/catalog.json)"
jsonnet -J vendor tests/coverage_gen.jsonnet > "$workdir/gen.json"
actual="$(jq length "$workdir/gen.json")"
[ "$actual" = "$expected" ] || { echo "::error::coverage generated $actual compositions, expected $expected"; exit 1; }
echo "generated $actual compositions from the catalog"

# Render every composition in ONE jsonnet process: a single invocation imports
# k8s-libsonnet once and shares it across all compositions, instead of paying the
# parse per snippet. Each snippet is a self-contained expression (the shape the
# per-case `-e` render used), keyed by name into one object.
manifests="$workdir/manifests"
mkdir -p "$manifests"
program="{"
while IFS="$(printf '\t')" read -r name snippet; do
  program+="\"${name}\": (${snippet}),"
done < <(jq -r '.[] | .name + "\t" + .snippet' "$workdir/gen.json")
program+="}"
if ! jsonnet -J vendor -e "$program" > "$workdir/rendered.json" 2>"$workdir/err"; then
  # A single bad composition fails the batch; jsonnet names it. Re-render per case
  # to attribute it plainly.
  cat "$workdir/err" >&2
  while IFS="$(printf '\t')" read -r name snippet; do
    jsonnet -J vendor -e "$snippet" >/dev/null 2>&1 || { echo "::error::composition $name failed to render"; exit 1; }
  done < <(jq -r '.[] | .name + "\t" + .snippet' "$workdir/gen.json")
  echo "::error::batched coverage render failed (see above)"; exit 1
fi

# Split every composition's List into one file per manifest — one jq pass, not one
# per composition.
jq -c '.[] | .items[]' "$workdir/rendered.json" \
  | split --lines=1 --additional-suffix=.json - "$manifests/manifest-"

# A persistent schema cache (shared with check-examples) and nproc-way parallelism
# so validation does not re-download the remote CRD schemas or bottleneck on a
# single core.
cache="${KUBECONFORM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform}"
mkdir -p "$cache"

# Validate every manifest — core kinds against the upstream schemas, CRD kinds
# (Gateway API) against the community catalog, exactly as check-examples does.
kubeconform -strict -summary \
  -cache "$cache" \
  -n "${KURLY_JOBS:-$(nproc)}" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/CustomResourceDefinition/catalog/main/schema/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  "$manifests"/*.json
