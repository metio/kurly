// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gitea-mirror — mirrors GitHub repositories into a Gitea (or Forgejo) instance
// on a schedule, with a web UI to pick what is mirrored. A plain composable
// kurly.http workload: it keeps its jobs, mirror history and account in a SQLite
// database on a PersistentVolume, so it needs no external database. Import it and
// render with kurly.list:
//
//   local giteaMirror = import 'github.com/metio/kurly/workloads/gitea-mirror/server.libsonnet';
//   kurly.list(giteaMirror())
//
// Serves the web UI and API on :4321 — compose an exposure onto it.
//
// PUBLIC URL: `publicUrl` is what the session cookies and OAuth callbacks are
// signed against, so it has to be the URL a browser actually reaches — a login
// that appears to succeed and then bounces back to the form is this value
// disagreeing with the address bar.
//
// SECRETS: left to itself the image mints a session key and an encryption key on
// first start and keeps them in dot-files on the volume, so restarts survive and
// nothing has to be authored. `secretName` takes that over, holding
// BETTER_AUTH_SECRET and ENCRYPTION_SECRET, for a deployment that wants those
// keys backed up and rotated somewhere other than the volume. The encryption key
// protects the stored forge tokens: losing it loses them.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gitea-mirror',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // The URL a browser reaches this at, e.g. https://mirror.example.com.
  publicUrl=null,
  // A Secret carrying BETTER_AUTH_SECRET and ENCRYPTION_SECRET.
  secretName=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4321)
  + kurly.servicePort(4321)
  + kurly.env(
    { HOST: '0.0.0.0', PORT: '4321', DATABASE_URL: 'file:/app/data/gitea-mirror.db' }
    + (if publicUrl != null then { BETTER_AUTH_URL: publicUrl } else {})
    + env
  )
  // The uid the image's own gitea-mirror user carries; fsGroup so the SQLite
  // database and the keys beside it are writable.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
