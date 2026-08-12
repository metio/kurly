// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kite — a Kubernetes dashboard: live resource views, logs, exec, and multi-
// cluster management from one page. A composable kurly.http workload holding its
// own users, sessions and audit log in a SQLite database on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local kite = import 'github.com/metio/kurly/workloads/kite/server.libsonnet';
//   kurly.list(kite(namespace='kite'))
//
// Serves the dashboard on :8080 — compose an exposure onto it.
//
// IT READS EVERYTHING IN THE CLUSTER, WHICH IS THE POINT AND THE RISK. A
// dashboard that showed only some kinds would be a dashboard with holes, so the
// grant is get/list/watch on every resource in every API group — including the
// Secrets of every namespace, because Kubernetes has no way to say "every kind
// except that one". Anyone who reaches this page sees what the cluster holds, so
// it belongs behind authentication and not on the open internet. `namespace` is
// where the ServiceAccount lives and is required, since a ClusterRoleBinding
// naming no namespace grants nothing.
//
// WRITES ARE NOT GRANTED HERE. Kite can edit and delete resources when its
// account may; this stage grants read only, and `extraRules` is where a
// deployment that wants an editing dashboard says so explicitly rather than
// inheriting it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='kite',
  image=defaultImage,
  // The namespace this is deployed into — the ClusterRoleBinding's subject needs
  // it, and a binding without one grants nothing at all.
  namespace='kite',
  storageSize='2Gi',
  storageClass=null,
  // Rules ADDED to the read-only grant: what an editing dashboard needs, stated
  // rather than inherited.
  extraRules=[],
  // A Prometheus for the resource graphs; without one the dashboard still works
  // and the charts stay empty.
  prometheusUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    { DB_DSN: '/data/kite.sqlite' }
    + (if prometheusUrl != null then { PROMETHEUS_URL: prometheusUrl } else {})
    + env
  )
  // Read-only across every group and kind. `*` rather than a list, because a
  // dashboard that enumerates groups stops showing a CRD the day somebody
  // installs one, and a dashboard with invisible gaps is worse than an honest
  // broad grant.
  + kurly.clusterRbac(
    [{ apiGroups: ['*'], resources: ['*'], verbs: ['get', 'list', 'watch'] }]
    + [{ nonResourceURLs: ['*'], verbs: ['get'] }]
    + extraRules,
    namespace=namespace
  )
  // The image runs as root and owns nothing that needs it; fsGroup makes the
  // database writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
