# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Stages the data the docs site reads into docs/assets/ (gitignored, so the
# published site is always generated from committed source). The assembler
# layout reads it with resources.Get and embeds the raw JSON verbatim, so the
# committed catalog/catalog.json — kept fresh by the check-catalog gate — is the
# single source of truth; this is a copy, not a second one.

mkdir -p docs/assets
cp catalog/catalog.json docs/assets/catalog.json
echo "staged docs/assets/catalog.json"
