// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// shipshipship — a ShipShipShip server (a public changelog and roadmap page for
// telling customers what shipped, what is being worked on and what is planned,
// edited from a Kanban board behind an admin login). A plain composable kurly.http
// workload keeping its SQLite database, uploads and installed themes on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local shipshipship = import 'github.com/metio/kurly/workloads/shipshipship/server.libsonnet';
//   kurly.list(shipshipship())
//
// Serves the public page and the admin interface on :8080 — compose an exposure
// onto it. The whole surface is public by design; only /admin asks for the
// credentials the Secret carries.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='shipshipship',
  image=defaultImage,
  // The SQLite database, uploaded images and any theme installed through the
  // admin interface all live here.
  storageSize='2Gi',
  storageClass=null,
  // The address the site is reached at. Only the newsletter uses it, to build the
  // links in the mail it sends — there is no sane default, so it stays unset and
  // the mails carry no working link until a deployment states its own.
  baseUrl=null,
  // The Secret holding ADMIN_USERNAME, ADMIN_PASSWORD and JWT_SECRET. JWT_SECRET
  // signs the admin session tokens: the image ships a published default, so
  // supplying one is the difference between an admin login only you can mint and
  // one anybody who read the source can.
  secretName='shipshipship',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
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
    {
      GIN_MODE: 'release',
      PORT: '8080',
      DB_PATH: '/app/data/changelog.db',
    }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // A single Go binary that selects no account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // The root path serves the public changelog once a theme is installed and the
  // admin interface until then, so what it answers with depends on how far setup
  // has got. Probe by connection, which is true in both states.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
