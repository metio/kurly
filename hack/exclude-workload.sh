#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Removes a workload from the catalogue completely: its directory, its annotation,
# its stage imports, every ledger entry keyed by it, and its smoke scenarios.
#
# It exists because removing one by hand touches nine files and missing one leaves
# the catalogue referring to something that is gone — the build fails helpfully for
# some of them and silently publishes a dangling claim for others.
#
# The DECISION belongs in catalog/excluded.libsonnet, which this does not write:
# an id there is refused by catalog.jsonnet if it is ever annotated again, and the
# reason beside it is what stops the removal being re-litigated. Add the entry
# first, then run this.
#
#   hack/exclude-workload.sh <id> [<id>...]
#
# Removing a workload does NOT unpublish it: images already released under
# ghcr.io/metio/kurly/workloads/<id> stay where they are, and anything pinning one
# by digest is unaffected.
set -euo pipefail

[ "$#" -gt 0 ] || { echo "usage: hack/exclude-workload.sh <id> [<id>...]" >&2; exit 1; }

for id in "$@"; do
  echo "== removing ${id} =="
  rm -rf "workloads/${id}"
  rm -f "hack/smoke/scenario-${id}.sh" "hack/smoke/prereq/${id}.sh"
  # The stage import map is hand-maintained, so its lines go by path.
  python3 - "$id" <<'PY'
import re, sys
wid = sys.argv[1]

def drop_object(path, keys):
    """Remove `key: { ... }` entries, brace-matched, so multi-line bodies go too."""
    try: s = open(path).read()
    except FileNotFoundError: return
    orig = s
    for key in keys:
        i = s.find(key)
        if i == -1: continue
        j = s.index('{', i); depth = 0; k = j
        while True:
            if s[k] == '{': depth += 1
            elif s[k] == '}': depth -= 1
            if depth == 0: break
            k += 1
        s = s[:i] + s[s.index('\n', k) + 1:]
    if s != orig: open(path, 'w').write(s); print(f"   pruned {path}")

for indent in ('    ', '  '):
    drop_object('catalog/annotations.libsonnet', (f"{indent}{wid}: {{", f"{indent}'{wid}': {{"))
    drop_object('catalog/upstream.gen.libsonnet', (f"{indent}{wid}: {{", f"{indent}'{wid}': {{"))

# Everything else is one line per workload (or per workload/stage).
line_keyed = [
    'catalog/catalog.jsonnet', 'catalog/delivered-verified.libsonnet',
    'catalog/e2e-verified.libsonnet', 'catalog/production.libsonnet',
    'catalog/database-use.libsonnet', 'catalog/resource-floors.libsonnet',
    'catalog/architectures.gen.libsonnet', 'catalog/bsi.gen.libsonnet',
    'catalog/maturity.gen.libsonnet', 'hack/smoke/known-failures.txt',
    'hack/smoke/extra.json',
]
key = re.compile(rf"""^\s*'?{re.escape(wid)}(/[a-z0-9-]+)?'?\s*:""")
for path in line_keyed:
    try: s = open(path).read()
    except FileNotFoundError: continue
    out = [l for l in s.split('\n')
           if not key.match(l)
           and f"workloads/{wid}/" not in l
           and not re.match(rf"^{re.escape(wid)}\s", l)]
    new = '\n'.join(out)
    if new != s: open(path, 'w').write(new); print(f"   pruned {path}")
PY
done

echo "== regenerating =="
jsonnetfmt -i catalog/*.libsonnet catalog/catalog.jsonnet
jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json
gen-smoke >/dev/null
gen-readme >/dev/null
echo "workloads now: $(jq '[.workloads[]]|length' catalog/catalog.json)"
