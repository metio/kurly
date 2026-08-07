// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// memtly — a Memtly server (event photo sharing: guests scan a QR code, view the
// gallery and upload their own photos and videos). A plain composable kurly.http
// workload keeping its SQLite database, uploads, thumbnails and custom branding on
// PersistentVolumes. Import it and render with kurly.list:
//
//   local memtly = import 'github.com/metio/kurly/workloads/memtly/server.libsonnet';
//   kurly.list(memtly())
//
// Serves the web app on :5000 — compose an exposure onto it.
//
// Single writer: a SQLite file and an upload directory on ReadWriteOnce volumes,
// so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='memtly',
  image=defaultImage,
  // The name shown in the header and the browser tab.
  title='Memtly',
  // The public URL, used in the links and QR codes handed to guests. Absent by
  // default: a URL that is wrong everywhere is worse than none.
  baseUrl=null,
  // Memtly redirects http to https itself by default. Behind an ingress that
  // terminates TLS the pod only ever sees http, so leaving it on redirects every
  // request back to a URL the ingress already served — turn it on again only where
  // the pod is reached over https directly.
  forceHttps=false,
  // SQLite in the config volume, the default the image ships. Point DATABASE_TYPE
  // and DATABASE_CONNECTION_STRING at an external server (mariadb, mysql,
  // postgres, mssql) through `env` to move the data off the volume.
  storageSize='20Gi',
  configStorageSize='1Gi',
  thumbnailStorageSize='5Gi',
  resourceStorageSize='1Gi',
  storageClass=null,
  // The Secret holding ENCRYPTION_KEY, ENCRYPTION_SALT and ACCOUNT_ADMIN_PASSWORD.
  // All three ship with published defaults upstream ('ChangeMe', 'ChangeMe' and
  // 'admin'), and the encryption key protects the values Memtly stores encrypted,
  // so supplying them is the difference between having a private gallery and not.
  secretName='memtly',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // Kestrel is pinned to :5000 in the application's own Program.cs (UseUrls), which
  // overrides the ASPNETCORE_HTTP_PORTS=8080 the base image sets.
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env(
    {
      TITLE: title,
      DATABASE_TYPE: 'sqlite',
      FORCE_HTTPS: std.toString(forceHttps),
      // ASP.NET writes its DataProtection keys under $HOME, and those keys decrypt
      // the auth cookies and anything else it protected. Pointing HOME at the
      // config volume keeps them across restarts and stops the path depending on
      // which uid runs; without it they are regenerated on every start, which logs
      // everybody out.
      HOME: '/app/config',
    }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image creates the account it means to run as (uid/gid 1654, APP_UID) but
  // never selects it, so it would run as root. fsGroup hands it the volumes.
  + kurly.runAs(1654, gid=1654, fsGroup=1654)
  // Four directories the application writes into, all inside its own install tree
  // at /app: the SQLite database and settings, the originals guests upload, the
  // thumbnails generated from them, and the branding an operator drops in.
  + kurly.store('/app/uploads', storageSize, storageClass=storageClass)
  + kurly.store('/app/config', configStorageSize, storageClass=storageClass)
  + kurly.store('/app/thumbnails', thumbnailStorageSize, storageClass=storageClass)
  + kurly.store('/app/custom_resources', resourceStorageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // Memtly stages uploads beside its own code rather than under /tmp, and the
  // root filesystem is read-only — without this the first write fails and the
  // process exits.
  + kurly.scratch('/app/temp')
  // The first start creates the database, seeds the admin account and applies
  // migrations before anything answers.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  // By connection: every page redirects to the login or the gallery selector, and
  // with FORCE_HTTPS on it redirects to https as well.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
