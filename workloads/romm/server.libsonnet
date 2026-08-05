// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// romm — a RomM server (scans a ROM library, enriches it with metadata from the
// games databases and browses or plays it in the browser). A composable kurly.http
// workload backed by an EXTERNAL MariaDB/MySQL — the mysql-cluster workload provides
// one — with the library, uploaded assets and scraped resources on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local romm = import 'github.com/metio/kurly/workloads/romm/server.libsonnet';
//   kurly.list(romm())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// The image bundles its own Valkey at :6379 and runs nginx plus the Python backend
// under s6, which starts as root and drops privileges, so this relaxes kurly's
// non-root and read-only-rootfs defaults.
//
// Single writer: the library lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='romm',
  image=defaultImage,
  // The ROM library, scraped resources, uploaded assets and the config file — all
  // under /romm, which is the one directory the image declares as its data volume.
  storageSize='100Gi',
  storageClass=null,
  // The MariaDB/MySQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='romm-db',
  dbPort=3306,
  database='romm',
  dbUser='romm',
  // The Secret holding DB_PASSWD and ROMM_AUTH_SECRET_KEY, plus whichever metadata
  // provider credentials you use (IGDB_CLIENT_ID/IGDB_CLIENT_SECRET,
  // MOBYGAMES_API_KEY, STEAMGRIDDB_API_KEY). kurly authors no Secret.
  secretName='romm',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
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
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named after this workload would otherwise inject ROMM_PORT as a
  // tcp:// URL into the container, on top of the ROMM_* names the application
  // reads its own configuration from.
  + kurly.disableServiceLinks()
  // s6 supervises nginx and the backend and drops privileges to their accounts,
  // which it can only do from root; the entrypoint also chowns the data volume.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx, s6 and the bundled Valkey all keep their pid files, sockets, logs and
  // /redis-data inside the image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/romm', storageSize, storageClass=storageClass)
  // A first start creates the schema and builds the library index, and a scan of a
  // large library keeps the backend busy well past a liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  // The application answers a redirect to the login page on / and requires a
  // session everywhere else, so it is probed by connection.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
