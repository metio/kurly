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
{
  // Base kinds — each a `function(name, image)` (cron also takes a schedule).
  http: import './http.libsonnet',
  worker: import './worker.libsonnet',
  cron: import './cron.libsonnet',
  daemon: import './daemon.libsonnet',

  // Composable axes.
  expose: import './expose.libsonnet',
  security: import './security.libsonnet',
  migrations: import './migrations.libsonnet',

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

  // listOf renders an explicit set of manifests as a `kind: List`, dropping any
  // null entries (an absent owned manifest, e.g. a workload with no store).
  listOf(manifests):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.filter(function(manifest) manifest != null, manifests),
  },

  // A workload's stages are the ORDERED, GATED phases of installing ONE
  // application — apply a phase, wait for it to go healthy, then the next — not
  // environment tiers. Each stage names a SUBSET of the app's manifests (place
  // a manifest handle like app.deployment or app.storeClaim in the phase it
  // belongs to); stageset-controller applies them in the order its StageSet
  // declares, gating between. Order manifests by real dependency, not by kind:
  // a PVC that binds WaitForFirstConsumer must ride in the same stage as the
  // pod that consumes it, or it never binds. Many workloads need only ONE stage
  // — do not manufacture ordering an application does not have.
  //
  //   stages([
  //     stage('data', [app.configMap, app.storeClaim]),
  //     stage('app', [app.deployment, app.service]),
  //   ])
  //
  // yields the stage-name → kind: List map the workload artifact pipeline packs
  // one OCI layer per stage from.
  stage(name, manifests):: { name: name, manifests: manifests },

  stages(stageList):: {
    [entry.name]: $.listOf(entry.manifests)
    for entry in stageList
  },
} + (import './features.libsonnet')
