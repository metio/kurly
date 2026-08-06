# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Checks the docs site's assembler — the browser component that turns a catalog
# entry plus a visitor's choices into a Jsonnet snippet and the JaaS manifests to
# deploy it. Everything it emits is code a visitor pastes into their cluster, so
# "it renders" is not enough: the snippet has to PARSE as Jsonnet and the wiring
# has to parse as YAML.
#
# The component runs in a browser, so the harness stubs the two globals it uses
# (document, Alpine) and drives it exactly as the page does: select a workload's
# stage, then read the outputs.
#
# It is checked against the workloads whose names break naive generators — a
# hyphenated id (no Jsonnet identifier may contain one), an id starting with a
# digit (nor may one start with that), and a multi-stage workload (whose StageSet
# has to carry every stage, each pointing at its own snippet, or the gating orders
# nothing).
set -euo pipefail

# .build/catalog.json is a BUILD ARTIFACT with no committed copy, so a fresh
# checkout does not have one — CI included. Producing it here rather than
# failing means a gate depends on the DATA it needs instead of on somebody
# having remembered to render it first, which is exactly the step a CI job
# forgot.
[ -f .build/catalog.json ] || gen-catalog >/dev/null
catalog=.build/catalog.json

echo "== assembler: syntax =="
node --check docs/static/js/assembler.js

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== assembler: render the outputs the page offers =="
node - "$catalog" "$work" <<'JS'
const fs = require('fs');
const [catalogPath, outDir] = process.argv.slice(2);
const catalog = fs.readFileSync(catalogPath, 'utf8');

// The two browser globals the component touches: the catalog is injected into a
// script tag by the layout, and Alpine registers the component factory.
let factory;
global.document = {
  addEventListener: (_event, fn) => fn(),
  getElementById: (id) => (id === 'kurly-catalog' ? { textContent: catalog } : null),
};
global.Alpine = { data: (_name, fn) => { factory = fn; } };
require(`${process.cwd()}/docs/static/js/assembler.js`);

const parsed = JSON.parse(catalog);
const pick = (id) => parsed.workloads.find((w) => w.id === id);
const multi = parsed.workloads.find((w) => w.stages.length > 1);
const cases = [pick('cal-com'), pick('2fauth'), multi].filter(Boolean);
if (cases.length === 0) { console.error('no representative workloads in the catalog'); process.exit(1); }

for (const w of cases) {
  const app = factory();
  app.init();
  app.select(w, w.stages[0]);
  fs.writeFileSync(`${outDir}/${w.id}.jsonnet`, app.snippet);
  fs.writeFileSync(`${outDir}/${w.id}.yaml`, app.jaas);
  // Every stage the workload declares has to appear in the StageSet, each
  // referencing a snippet of its own.
  for (const stage of w.stages) {
    if (!app.jaas.includes(`- name: ${stage.id}\n`)) {
      console.error(`${w.id}: the StageSet is missing stage ${stage.id}`);
      process.exit(1);
    }
  }
  // Anchored: a stage's sourceRef names the same kind, indented.
  const snippets = (app.jaas.match(/^kind: JsonnetSnippet$/gm) || []).length;
  if (snippets !== w.stages.length) {
    console.error(`${w.id}: ${snippets} snippet(s) for ${w.stages.length} stage(s)`);
    process.exit(1);
  }
  console.log(`rendered ${w.id} (${w.stages.length} stage(s))`);
}
JS

echo "== assembler: the snippets parse as Jsonnet =="
for file in "$work"/*.jsonnet; do
  # jsonnetfmt parses without resolving imports, which is exactly the check here:
  # the snippet names libraries that only exist inside a cluster. Its output is
  # discarded — a snippet is generated code, so only whether it PARSES matters,
  # not whether it matches the formatter's layout.
  jsonnetfmt "$file" >/dev/null || {
    echo "::error::${file##*/} does not parse as Jsonnet:"
    jsonnetfmt "$file" 2>&1 >/dev/null | head -5
    exit 1
  }
  echo "ok: ${file##*/} parses"
done

echo "== assembler: the JaaS wiring parses as YAML =="
for file in "$work"/*.yaml; do
  yq --exit-status 'true' "$file" >/dev/null || {
    echo "::error::${file##*/} does not parse as YAML"; exit 1;
  }
  echo "ok: ${file##*/} parses"
done

echo "assembler outputs parse for every representative workload"
