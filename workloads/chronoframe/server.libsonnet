// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chronoframe — a ChronoFrame server (a personal photo gallery browsing your own
// pictures by map, timeline and EXIF). A plain composable kurly.http workload
// keeping its SQLite database and — with the default local storage provider —
// the photos themselves on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local chronoframe = import 'github.com/metio/kurly/workloads/chronoframe/server.libsonnet';
//   kurly.list(chronoframe())
//
// Serves the gallery and its API on :3000 — compose an exposure onto it.
//
// The image ships with the S3 storage provider selected, which cannot work until
// somebody supplies a bucket; this stage selects the LOCAL provider instead, so a
// default render stores photos under /app/data/storage on the volume and runs
// without any external dependency. Point env at the S3 keys to move them off.
//
// Map tiles, reverse geocoding and OAuth are all reached over the internet at
// runtime, so a NetworkPolicy composed onto this workload has to allow egress or
// the map stays blank while everything else keeps working.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='chronoframe',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // The address of the administrator account created on first start.
  adminEmail='admin@chronoframe.com',
  // The Secret holding NUXT_SESSION_PASSWORD (which encrypts the session cookie
  // and must be 32 characters), NUXT_OG_IMAGE_SECRET (which signs generated
  // preview images) and CFRAME_ADMIN_PASSWORD. Without it the image falls back
  // to its published default administrator password.
  secretName='chronoframe',
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
  + kurly.env({
    NITRO_HOST: '0.0.0.0',
    NITRO_PORT: '3000',
    DATABASE_URL: './data/app.sqlite3',
    NUXT_STORAGE_PROVIDER: 'local',
    NUXT_PROVIDER_LOCAL_PATH: './data/storage',
    NUXT_PROVIDER_LOCAL_BASE_URL: '/storage',
    CFRAME_ADMIN_EMAIL: adminEmail,
  } + env)
  + kurly.envFromSecret(secretName)
  // The image selects no account and needs nothing root provides; the volume is
  // handed over by fsGroup.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // exiftool reads and writes temporary files while extracting EXIF from an
  // upload, and the root filesystem is read-only.
  + kurly.scratch('/tmp')
  // Nitro reads PORT, which is exactly what a Service named after this workload
  // would inject as a tcp:// URL.
  + kurly.disableServiceLinks()
  // The first start applies the database migrations before it serves.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
