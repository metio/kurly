// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// plumio — a Plumio server (Markdown notes with a live preview, optional
// end-to-end encryption, and organisations several people share). A plain
// composable kurly.http workload: notes live as files beside a SQLite database on
// a PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local plumio = import 'github.com/metio/kurly/workloads/plumio/server.libsonnet';
//   kurly.list(plumio())
//
// Serves the web app on :3000 — compose an exposure onto it. The image runs two
// Node processes: the API on :3001 and the web front end on :3000, which PROXIES
// /api/* to the API itself, so only :3000 is published and a browser needs nothing
// else. The API port stays off the Service deliberately; publishing it invites a
// second route to the same data with none of the front end's own handling.
//
// Single writer: one SQLite database and the note files on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='plumio',
  image=defaultImage,
  // The SQLite database and the note files.
  storageSize='5Gi',
  storageClass=null,
  // The Secret holding JWT_SECRET and ENCRYPTION_KEY. The image ships neither, and
  // both are load-bearing: JWT_SECRET signs the tokens users hold, ENCRYPTION_KEY
  // is what makes an encrypted note readable again. Losing the latter loses the
  // notes it protected — no reset restores them.
  secretName='plumio',
  // The URL users reach this instance at. It reaches the app as APP_URL (the links
  // it puts in mail) and ALLOWED_ORIGINS (which browser origins the API answers).
  // Absent by default, because a default here would be wrong everywhere it is
  // really deployed.
  appUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    {
      NODE_ENV: 'production',
      BACKEND_INTERNAL_PORT: '3001',
      DB_PATH: '/data/plumio.db',
      DOCUMENTS_PATH: '/data/documents',
    }
    + (if appUrl == null then {} else { APP_URL: appUrl, ALLOWED_ORIGINS: appUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // The Node front-end server writes its cached chunks under the system temporary
  // directory, which the read-only root filesystem otherwise refuses.
  + kurly.scratch('/tmp', '64Mi')
  // The start script gives the API five seconds before it starts the front end,
  // and the API opens the database and applies its schema in that window.
  + kurly.startupProbe({ httpGet: { path: '/api/health', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
