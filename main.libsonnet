// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kurly — a bookstore of Kubernetes workload recipes, written in Jsonnet on
// top of k8s-libsonnet. Pick a kind, give it a name and an image, and chain
// with* modifiers; the visible fields of the result are the manifests.
// Exposure and the security profile are separate, composable axes: add an
// expose recipe or a security profile with `+`.
{
  http: import './http.libsonnet',
  worker: import './worker.libsonnet',
  cron: import './cron.libsonnet',
  daemon: import './daemon.libsonnet',
  expose: import './expose.libsonnet',
  security: import './security.libsonnet',
  migrations: import './migrations.libsonnet',

  // list renders every manifest of an app as a single `kind: List`, ready for
  // `kubectl apply --filename -` or as a JsonnetSnippet's published output.
  list(app):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.objectValues(app),
  },

  // stages declares per-stage layers of one workload: each overlay is a mixin
  // composed onto the app, keyed by stage name (stageset-controller's stages).
  // The result maps stage name → composed app, still open for further
  // composition; stageLists renders each stage straight to a `kind: List` —
  // the shape the workload artifact pipeline packs one OCI layer per stage
  // from.
  stages(app, overlays):: {
    [stage]: app + overlays[stage]
    for stage in std.objectFields(overlays)
  },

  stageLists(app, overlays):: {
    [stage]: $.list(app + overlays[stage])
    for stage in std.objectFields(overlays)
  },
}
