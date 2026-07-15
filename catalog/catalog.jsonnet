// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Generates catalog.json: the machine-readable model of kurly's public API the
// assembler UI (and any docs renderer) reads. The annotations carry the prose,
// parameter types, and composition facets; this file cross-checks them against
// the REAL exported fields of each library module and fails to render if the two
// diverge — so a feature added without an annotation, or an annotation left
// behind after a feature is removed, breaks the build rather than shipping a
// catalog that lies. Render from the repo root:
//
//   jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json
local expose = import '../lib/expose.libsonnet';
local features = import '../lib/features.libsonnet';
local migrations = import '../lib/migrations.libsonnet';
local security = import '../lib/security.libsonnet';
local main = import '../main.libsonnet';
local ann = import './annotations.libsonnet';

// Fails if the annotated names and the exported names are not the same set,
// naming exactly which side is out of step.
local reconcile(section, annotated, exported) =
  local a = std.set(annotated);
  local e = std.set(exported);
  local unannotated = [name for name in e if !std.member(a, name)];
  local stale = [name for name in a if !std.member(e, name)];
  assert unannotated == [] :
         section + ': exported but not annotated in annotations.libsonnet: ' + std.join(', ', unannotated);
  assert stale == [] :
         section + ': annotated but not exported (stale annotation): ' + std.join(', ', stale);
  true;

// One catalog entry per annotated field, id-keyed and sorted for a stable diff.
local entries(section) = [
  { id: name } + section[name]
  for name in std.objectFields(section)
];

{
  // Drift gates — object-level asserts fire when this object is manifested.
  assert reconcile('features', std.objectFields(ann.features), std.objectFieldsAll(features)),
  assert reconcile('expose', std.objectFields(ann.expose), std.objectFieldsAll(expose)),
  assert reconcile('security', std.objectFields(ann.security), std.objectFieldsAll(security)),
  assert reconcile('migrations', std.objectFields(ann.migrations), std.objectFieldsAll(migrations)),
  // Kinds live in separate files; assert the annotated set is exactly the four
  // main exposes as callables.
  assert reconcile('kinds', std.objectFields(ann.kinds), ['http', 'worker', 'cron', 'daemon']),
  assert std.all([std.objectHasAll(main, kind) for kind in std.objectFields(ann.kinds)]) :
         'kinds: main.libsonnet must expose every annotated kind',

  schemaVersion: 1,
  kinds: entries(ann.kinds),
  features: entries(ann.features),
  expose: entries(ann.expose),
  security: entries(ann.security),
  migrations: entries(ann.migrations),
}
