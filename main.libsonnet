// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kurly — a bookstore of Kubernetes workload recipes, written in Jsonnet on
// top of k8s-libsonnet. Pick a kind, give it a name and an image, and chain
// with* modifiers; the visible fields of the result are the manifests.
{
  web: import './web.libsonnet',
  api: import './api.libsonnet',
  worker: import './worker.libsonnet',
  cron: import './cron.libsonnet',
  daemon: import './daemon.libsonnet',

  // list renders every manifest of an app as a single `kind: List`, ready for
  // `kubectl apply --filename -` or as a JsonnetSnippet's published output.
  list(app):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.objectValues(app),
  },
}
