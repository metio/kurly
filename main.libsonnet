// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kurly — a bookstore of Kubernetes workload recipes, written in Jsonnet on
// top of k8s-libsonnet. Start from a kind (a base "default" for that shape),
// then add capabilities as composable `+` features; the visible fields of the
// result are the manifests.
//
//   kurly.http('tik', image)                 // the base
//   + kurly.args(['backend', '--config=…'])  // features, in any order
//   + kurly.store('/var/lib/tik', '1Gi')
//   + kurly.runAs(12345)
//   + kurly.expose.gateway(host, 'shared')   // exposure & security are features too
//
// A feature only ever contributes to the hidden `config`, so the manifests
// late-bind against the merged config regardless of compose order. Exposed as
// a JsonnetLibrary for JaaS: author a workload as `function(params) …` and
// JaaS feeds the parameters as TLAs.

// Builds one flat array from parts that may be null (dropped) or nested arrays
// (flattened in one level), so a caller assembles a set with conditionals and
// optional groups. `if cond then value` with no else is null when cond is
// false, so an unmet condition simply drops out.
local join(parts) =
  local flatten(acc, part) =
    if std.isArray(part) then acc + part else acc + [part];
  std.foldl(flatten, std.filter(function(part) part != null, parts), []);

{
  // Base kinds — each a `function(name, image)` (cron also takes a schedule).
  http: import './lib/http.libsonnet',
  worker: import './lib/worker.libsonnet',
  cron: import './lib/cron.libsonnet',
  daemon: import './lib/daemon.libsonnet',

  // Composable axes.
  expose: import './lib/expose.libsonnet',
  security: import './lib/security.libsonnet',
  migrations: import './lib/migrations.libsonnet',

  // list renders every manifest of an app as a single `kind: List`, ready for
  // `kubectl apply --filename -` or as a JsonnetSnippet's published output.
  // The app's owned manifests (its store PVC, its config ConfigMap) ride along
  // — they are hidden fields, so std.objectValues skips them.
  list(app):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.objectValues(app)
           + (if std.objectHasAll(app, 'ownedManifests') then app.ownedManifests else []),
  },

  // join builds one flat array from parts that may be null or nested arrays —
  // assemble the parts of a value (a list of manifests, a set of args) with
  // conditionals and optional groups:
  //
  //   kurly.join([
  //     alwaysThis,
  //     if enabled then optionalThis,   // dropped when `enabled` is false
  //     [aGroupOfThings],               // flattened in
  //   ])
  join(parts):: join(parts),

  // listOf renders an explicit set of manifests as a `kind: List`. It joins the
  // parts first, so entries can be null (dropped — e.g. an absent owned
  // manifest) or nested arrays (flattened), letting a consumer build the set
  // with the same conditionals and optional groups as join.
  listOf(parts):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.filter(function(manifest) manifest != null, join(parts)),
  },

  // A workload's stages are the ORDERED, GATED phases of installing ONE
  // application — apply a phase, wait for it to go healthy, then the next — not
  // environment tiers. Each stage is its OWN file under workloads/<name>/: a
  // `function(params)` returning a COMPOSABLE app (a base with defaults, no
  // exposure), which a consumer imports, adapts with `+` features, and renders
  // with kurly.list — one stage file maps to one stageset stage. Many workloads
  // need only ONE stage; do not manufacture ordering an application lacks.
  // (A PVC that binds WaitForFirstConsumer must ride with the pod that consumes
  // it, so it cannot be gated into a stage of its own.)
} + (import './lib/features.libsonnet')
