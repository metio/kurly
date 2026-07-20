# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Fail if any workload README's generated JaaS/stageset section is stale. Runs the
# generator in check mode, so it never mutates the tree — the same discipline
# check-catalog follows for catalog.json.

set -euo pipefail

exec env KURLY_README_CHECK=1 gen-readme
