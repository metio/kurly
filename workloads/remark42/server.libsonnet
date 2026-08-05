// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// remark42 — a Remark42 server (a lightweight comment engine for static sites and
// blogs: drop a script tag on a page and readers can comment, signing in with
// social providers or anonymously). A plain composable kurly.http workload: the
// comments live in an embedded BoltDB on a PersistentVolume, so it needs nothing
// external. Import it and render with kurly.list:
//
//   local remark42 = import 'github.com/metio/kurly/workloads/remark42/server.libsonnet';
//   kurly.list(remark42(siteUrl='https://comments.example.com'))
//
// Serves the API and the embedded widget on :8080 — compose an exposure onto it.
//
// Single writer: one BoltDB file on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). BoltDB takes a single writer lock, so a second pod
// does not corrupt the file — it simply never opens it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='remark42',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The URL remark42 is served at. REQUIRED: it is baked into the widget script
  // and into every OAuth callback, so a wrong value produces comments that load
  // nowhere and logins that return to the wrong host.
  siteUrl=null,
  // The sites the widget is allowed to serve comments for, as remark42's SITE id.
  site='remark',
  // The Secret holding SECRET, which signs the JWTs readers hold. remark42 refuses
  // to start without it, which is the right behaviour and the reason kurly mints
  // none.
  secretName='remark42',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
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
    { SITE: site }
    + (if siteUrl == null then {} else { REMARK_URL: siteUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The entrypoint sets the timezone, chowns /srv and drops to the `app` account —
  // but only when it starts as root, testing `id -u` first. Naming that account
  // (1001, the uid the image builds) takes the other path, so the hardened posture
  // holds and fsGroup makes the volume writable instead.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/srv/var', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
