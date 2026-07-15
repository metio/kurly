# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog-driven coverage battery: render every feature / exposure recipe /
# security profile / kind composition that tests/coverage_gen.jsonnet builds from
# the catalog, and validate each manifest with kubeconform. Because the set is
# generated straight from catalog.json, every annotated entry is exercised on
# every kind it claims legal — a newly annotated feature is covered with no test
# authoring, and a generator gap is caught by the count assertion. check-catalog
# keeps the catalog itself honest against the library.

jb install

# The compositions import kurly by its canonical path; resolve it via the vendor
# symlink, exactly as check-examples does.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# The expected composition count derives straight from the catalog (one per
# feature×kind, plus one per exposure recipe, security profile, and kind), so a
# generator that silently skips an entry fails here.
expected="$(jq '([.features[].kinds | length] | add) + (.expose | length) + (.security | length) + (.kinds | length)' catalog/catalog.json)"
jsonnet -J vendor tests/coverage_gen.jsonnet > "$workdir/gen.json"
actual="$(jq length "$workdir/gen.json")"
[ "$actual" = "$expected" ] || { echo "::error::coverage generated $actual compositions, expected $expected"; exit 1; }
echo "generated $actual compositions from the catalog"

# Render each composition and split its List into one file per manifest (the
# shape kubeconform validates) under a dedicated dir, so the generator's own
# gen.json array is not itself handed to kubeconform. A render failure trips
# pipefail and fails the gate.
manifests="$workdir/manifests"
mkdir -p "$manifests"
jq -r '.[] | .name + "\t" + .snippet' "$workdir/gen.json" > "$workdir/cases.tsv"
while IFS="$(printf '\t')" read -r name snippet; do
  jsonnet -J vendor -e "$snippet" \
    | jq -c '.items[]' \
    | split --lines=1 --additional-suffix=.json - "$manifests/$name-"
done < "$workdir/cases.tsv"

# Validate every manifest — core kinds against the upstream schemas, CRD kinds
# (Gateway API) against the community catalog, exactly as check-examples does.
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  "$manifests"/*.json
