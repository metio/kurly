// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// portabase — scheduled backups and on-demand restores for the databases you
// already run, with a web interface to drive them. A composable kurly.http
// workload: the backup files land on a PersistentVolume and Portabase's own
// records in a PostgreSQL. Import it and render with kurly.list:
//
//   local portabase = import 'github.com/metio/kurly/workloads/portabase/server.libsonnet';
//   kurly.list(portabase(secretName='portabase'))
//
// Serves the web interface on :80 — compose an exposure onto it.
//
// GIVE IT A DATABASE OF ITS OWN, OR IT STARTS ONE INSIDE THE POD. Without
// DATABASE_URL the image's entrypoint initialises and runs a PostgreSQL cluster
// in the container itself, on the container's own filesystem — which a restart
// discards, taking every schedule and every record of what was backed up with it.
// `secretName` carrying DATABASE_URL is what makes it durable, and is why this
// stage declares a database dependency rather than treating it as optional.
//
// THE BACKUPS ARE ONLY AS SAFE AS THIS VOLUME. Portabase writes them to /data,
// which is one PersistentVolume in the same cluster as the databases it is
// protecting. That is a backup against a dropped table, not against losing the
// cluster — compose a kurly.backup axis onto this workload, or point Portabase at
// off-cluster storage, before calling it disaster recovery.
//
// IT NEEDS CREDENTIALS FOR EVERYTHING IT BACKS UP, so this pod holds the keys to
// every database it touches; a NetworkPolicy limiting its egress to exactly those
// is worth composing on.
//
// The entrypoint runs as root: it starts tusd for resumable uploads, the
// application server, and nginx on :80, editing configuration in place first — so
// root, escalation, the runtime capabilities and a writable root filesystem are
// relaxed deliberately.
//
// Single writer: one backup directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='portabase',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  // A Secret carrying DATABASE_URL — see the header for what happens without it.
  secretName=null,
  // Set when something in front terminates TLS, so resumable uploads build the
  // right URLs.
  behindTlsProxy=true,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    (if behindTlsProxy then { TUSD_BEHIND_PROXY: 'true' } else {})
    + env
  )
  // See the header: the entrypoint rewrites configuration and starts three
  // processes as root before nginx binds :80.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
