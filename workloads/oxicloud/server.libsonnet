// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// oxicloud — file storage and sharing with a web interface, written in Rust. A
// plain composable kurly.http workload: the files themselves go to a
// PersistentVolume and the metadata to an external PostgreSQL. Import it and
// render with kurly.list:
//
//   local oxicloud = import 'github.com/metio/kurly/workloads/oxicloud/server.libsonnet';
//   kurly.list(oxicloud(secretName='oxicloud', baseUrl='https://files.example.com'))
//
// Serves the web app and API on :8086 — compose an exposure onto it.
//
// BASE URL: `baseUrl` is what OxiCloud builds share links and OIDC redirects
// from. Behind a reverse proxy it has to be the address a browser reaches, not
// the Service name — share links that resolve only inside the cluster are this
// value left at its default.
//
// RUNNING IT UNPRIVILEGED. The image's entrypoint chowns the storage volume and
// drops privileges with su-exec when it starts as root, and says in as many words
// that a start as an unprivileged user assumes the volume permissions are already
// right — which is what fsGroup does. So the stage runs as the image's own uid
// 1001 and keeps the hardened posture rather than taking the root path.
//
// Single writer: the blob store is one directory on a ReadWriteOnce volume, so
// one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='oxicloud',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // The URL a browser reaches this at.
  baseUrl=null,
  // A Secret carrying OXICLOUD_DB_CONNECTION_STRING — the PostgreSQL URL, whose
  // password is why it is a Secret rather than an env value here.
  secretName='oxicloud',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8086)
  + kurly.servicePort(8086)
  + kurly.env(
    { MIMALLOC_PURGE_DELAY: '0' }
    + (if baseUrl != null then { OXICLOUD_BASE_URL: baseUrl } else {})
    + env
  )
  // The uid the image's own oxicloud user carries — see the header for why that
  // avoids the root path its entrypoint would otherwise take.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/app/storage', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
