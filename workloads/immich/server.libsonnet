// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// immich server — the API and web app of Immich, a self-hosted photo and video
// backup. It keeps the original assets and generated thumbnails on a
// PersistentVolume mounted at /data (Immich's UPLOAD_LOCATION), and reaches a
// PostgreSQL with the VectorChord extension (for smart search) and a Redis for
// its job queue. Compose it with the machine-learning stage, a cnpg-cluster on a
// VectorChord image, and a valkey:
//
//   local server = import 'github.com/metio/kurly/workloads/immich/server.libsonnet';
//   kurly.list(server())
//
// Serves on :2283 — compose an exposure onto it.
//
// One writer on a ReadWriteOnce media volume, so one replica, recreated (never
// rolled) to keep two pods off the library. Point `storageClass` at a
// ReadWriteMany class and raise the replicas to run several.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='immich',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  database='immich',
  dbUser='immich',
  dbHost='immich-db-rw',
  redisHost='immich-cache-headless',
  machineLearningUrl='http://immich-machine-learning:3003',
  secretName='immich',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(2283)
  + kurly.servicePort(2283)
  // Immich writes thumbnails and geodata across its root filesystem, and the
  // official image starts as root; pin a non-root uid that owns the media volume
  // and keep the root filesystem writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // The non-secret connection settings. The password lives in `secretName` as
  // DB_PASSWORD — an Immich-shaped Secret the operator supplies (kurly mints no
  // Secret), typically filled from the CNPG cluster's own <cluster>-app Secret
  // via kurly.externalSecret. Any other value the Secret carries (REDIS_PASSWORD,
  // a full DB_URL) overrides the matching env below.
  + kurly.env({
    DB_HOSTNAME: dbHost,
    DB_DATABASE_NAME: database,
    DB_USERNAME: dbUser,
    DB_VECTOR_EXTENSION: 'vectorchord',
    REDIS_HOSTNAME: redisHost,
    IMMICH_MACHINE_LEARNING_URL: machineLearningUrl,
  } + env)
  + kurly.envFromSecret(secretName)
  // The Service is named after the app, so the Service-link environment defines
  // IMMICH_PORT as a tcp:// URL — which the server parses as its listen port.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/api/server/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/server/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
