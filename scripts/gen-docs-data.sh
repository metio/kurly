# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Stages the generated inputs the docs site needs into gitignored paths, so the
# published site is always built from committed source (the catalog) and a
# version-pinned dependency (Alpine), never from a committed build artifact.
# Renovate keeps ALPINE_VERSION current (see the customManager in renovate.json).

# Alpine.js drives the assembler page. It is fetched here rather than vendored so
# a version bump is a one-line Renovate PR, not a hand-committed binary blob.
# .build/catalog.json is a BUILD ARTIFACT with no committed copy, so a fresh
# checkout does not have one — CI included. Producing it here rather than
# failing means a gate depends on the DATA it needs instead of on somebody
# having remembered to render it first, which is exactly the step a CI job
# forgot.
[ -f .build/catalog.json ] || gen-catalog >/dev/null

ALPINE_VERSION=3.15.12

mkdir -p docs/assets docs/static docs/static/js

# The catalog: assets/ is read by resources.Get and embedded into the assembler
# and reference pages; static/ is published verbatim at /catalog.json for
# programmatic consumers (and linked from the reference page and llms.txt). The
# committed .build/catalog.json — kept fresh by check-catalog — is the single
# source of truth; these are copies, not a second one.
cp .build/catalog.json docs/assets/catalog.json
cp .build/catalog.json docs/static/catalog.json

curl -fsSL "https://cdn.jsdelivr.net/npm/alpinejs@${ALPINE_VERSION}/dist/cdn.min.js" \
  -o docs/static/js/alpine.min.js

echo "staged catalog.json (assets + static) and alpine.min.js ${ALPINE_VERSION}"
