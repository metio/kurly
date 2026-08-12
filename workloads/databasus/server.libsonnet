// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// databasus — scheduled backups for the PostgreSQL, MySQL and MongoDB databases
// you already run, with a web interface, restore, and notifications when a run
// fails. A composable kurly.http workload. Import it and render with kurly.list:
//
//   local databasus = import 'github.com/metio/kurly/workloads/databasus/server.libsonnet';
//   kurly.list(databasus())
//
// Serves the web interface on :4005 — compose an exposure onto it.
//
// IT RUNS ITS OWN POSTGRESQL INSIDE THE POD, AND THERE IS NO WAY OUT. The image
// starts an embedded PostgreSQL for its own schedules and history, on the same
// volume as the backups it takes. That is one PersistentVolume holding both the
// backups and the only record of what was backed up, in the same cluster as the
// databases it protects — a defence against a dropped table, not against losing
// the cluster. Send the backups off-cluster, or compose a kurly.backup axis onto
// this volume, before calling it disaster recovery.
//
// THE ENTRYPOINT NEEDS ROOT. It reconciles the embedded postgres user's uid,
// chowns three directories under the data volume, and writes the frontend's
// runtime configuration into the image tree before starting anything — so root,
// escalation, the runtime capabilities and a writable root filesystem are relaxed
// deliberately rather than pretended away.
//
// IT HOLDS CREDENTIALS FOR EVERYTHING IT BACKS UP, so a NetworkPolicy limiting
// its egress to exactly those databases is worth composing on.
//
// Single writer: one data directory on a ReadWriteOnce volume, with a database
// inside it, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='databasus',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  // The URL a browser reaches this at; the notification mails link to it, and it
  // is half of what turns email on.
  publicUrl=null,
  // A Secret carrying the SMTP credentials and any OAuth client secrets.
  secretName=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4005)
  + kurly.servicePort(4005)
  + kurly.env(
    (if publicUrl != null then { DATABASUS_URL: publicUrl } else {})
    + env
  )
  // See the header: the entrypoint reconciles uids, chowns the data directory and
  // rewrites the frontend configuration in the image tree, all as root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  // The embedded PostgreSQL, the backup files and the temporary spool, all under
  // one claim because the image puts them there.
  + kurly.store('/databasus-data', storageSize, storageClass=storageClass)
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // The embedded database is initialised on first start, which takes longer than
  // a liveness probe should wait.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
