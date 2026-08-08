// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// onloc — an Onloc API server (records where your devices report themselves to be,
// for the companion application to read back). A plain composable kurly.http
// workload backed by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides
// one — with uploaded avatars on a PersistentVolume. Import it, point it at a
// database, and render with kurly.list:
//
//   local onloc = import 'github.com/metio/kurly/workloads/onloc/server.libsonnet';
//   kurly.list(onloc())
//
// Serves the API, the websocket and /uploads on :4000 — compose an exposure onto
// it. This is the BACK END only; the companion web interface is a separate image.
//
// DATABASE & SECRETS: Onloc reads DATABASE_URL (a Prisma PostgreSQL URL, with the
// password embedded) and the two token secrets from the environment. kurly authors
// no Secret; provide one holding all three, pulled in via envFrom. The two token
// secrets FALL BACK to values published in the source when unset, so supplying them
// is the difference between tokens anybody can mint and tokens they cannot. The
// defaults pair with a cnpg-cluster named onloc-db.
//
// The container runs `prisma migrate deploy` before it serves, so a first start on
// an empty database takes longer than a liveness delay should allow — hence the
// startup probe.
//
// Single writer: uploaded avatars live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='onloc',
  image=defaultImage,
  // Uploaded avatars.
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding DATABASE_URL, ACCESS_TOKEN_SECRET and REFRESH_TOKEN_SECRET
  // (kurly mints none), via envFrom.
  secretName='onloc',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4000)
  + kurly.servicePort(4000)
  // The server listens on 3000 unless PORT says otherwise, and the port a stage
  // declares has to be the port the image actually binds.
  + kurly.env({ PORT: '4000' } + env)
  + kurly.envFromSecret(secretName)
  // The image selects no account and needs nothing root provides; uid 1000 exists
  // in it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/uploads', storageSize, storageClass=storageClass)
  // Prisma's migration engine unpacks and writes there.
  + kurly.scratch('/tmp')
  // The request log is written beside the application's own code, and its
  // logging middleware creates the directory before it serves anything — on a
  // read-only root that mkdir fails and the process exits. It is a log, so a
  // scratch is the right home; the directory holds nothing the image ships.
  + kurly.scratch('/app/logs')
  + kurly.startupProbe({ httpGet: { path: '/api/health', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
