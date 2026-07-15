# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog gate: regenerate catalog/catalog.json from the library annotations
# and fail if the committed copy is stale. Rendering it also runs the drift
# asserts in catalog.jsonnet (a feature exported without an annotation, or an
# annotation with no matching export, fails here) — so the machine-readable API
# model the assembler reads can never silently disagree with the library.

# The generator imports the library, which imports k8s-libsonnet; vendor it.
jb install

generated="$(jsonnet -J vendor catalog/catalog.jsonnet)"

if ! diff -u catalog/catalog.json <(printf '%s\n' "$generated") >/dev/null; then
  echo "catalog/catalog.json is stale — regenerate it:" >&2
  echo "  jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json" >&2
  echo >&2
  diff -u catalog/catalog.json <(printf '%s\n' "$generated") >&2 || true
  exit 1
fi
echo "catalog is in sync with the library"
