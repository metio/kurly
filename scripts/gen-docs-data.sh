# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Stages the generated inputs the docs site needs into gitignored paths, so the
# published site is always built from committed source (the catalog) and a
# version-pinned dependency (Alpine), never from a committed build artifact.
# Renovate keeps ALPINE_VERSION current (see the customManager in renovate.json).

# Alpine.js drives the assembler page. It is fetched here rather than vendored so
# a version bump is a one-line Renovate PR, not a hand-committed binary blob.
ALPINE_VERSION=3.14.9

mkdir -p docs/assets docs/static docs/static/js

# The catalog: assets/ is read by resources.Get and embedded into the assembler
# and reference pages; static/ is published verbatim at /catalog.json for
# programmatic consumers (and linked from the reference page and llms.txt). The
# committed catalog/catalog.json — kept fresh by check-catalog — is the single
# source of truth; these are copies, not a second one.
cp catalog/catalog.json docs/assets/catalog.json
cp catalog/catalog.json docs/static/catalog.json

curl -fsSL "https://cdn.jsdelivr.net/npm/alpinejs@${ALPINE_VERSION}/dist/cdn.min.js" \
  -o docs/static/js/alpine.min.js

echo "staged catalog.json (assets + static) and alpine.min.js ${ALPINE_VERSION}"
