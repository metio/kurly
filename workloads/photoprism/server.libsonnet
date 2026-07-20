// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// photoprism — a PhotoPrism server (an AI-powered, self-hosted photo-management app
// with face recognition and automatic tagging). A plain composable kurly.http
// workload on the official image: with the SQLite backend its database, cache, and
// originals live on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local photoprism = import 'github.com/metio/kurly/workloads/photoprism/server.libsonnet';
//   kurly.list(photoprism(siteUrl='https://photos.example.com/'))
//
// Serves the web app and API on :2342 — compose an exposure onto it.
//
// The image runs its indexing (TensorFlow) and thumbnailer and writes across the root
// filesystem, so this relaxes the read-only-rootfs default while keeping non-root,
// dropped capabilities, and no privilege escalation.
//
// SECRETS: PhotoPrism reads PHOTOPRISM_ADMIN_PASSWORD from the environment. kurly
// authors no Secret; provide one holding it, pulled in via envFrom.
//
// Single writer: the database, cache, and originals live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files. Point
// PHOTOPRISM_DATABASE_DRIVER at external MariaDB (the mysql-cluster workload) to scale
// past the single SQLite writer.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='photoprism',
  image='docker.io/photoprism/photoprism:260601',
  storageSize='50Gi',
  storageClass=null,
  // The public URL PhotoPrism builds links against (required; keep the trailing /).
  siteUrl=null,
  adminUser='admin',
  // The Secret holding PHOTOPRISM_ADMIN_PASSWORD (kurly mints none), via envFrom.
  secretName='photoprism-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    PHOTOPRISM_DATABASE_DRIVER: 'sqlite',
    PHOTOPRISM_HTTP_PORT: '2342',
    PHOTOPRISM_HTTP_HOST: '0.0.0.0',
    PHOTOPRISM_STORAGE_PATH: '/photoprism/storage',
    PHOTOPRISM_ORIGINALS_PATH: '/photoprism/originals',
    PHOTOPRISM_ADMIN_USER: adminUser,
  } + (if siteUrl == null then {} else { PHOTOPRISM_SITE_URL: siteUrl });

  local originals = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/photoprism/originals', subPath: 'originals' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(2342)
  + kurly.servicePort(2342)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/photoprism/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/status', port: 'http' }, initialDelaySeconds: 20, periodSeconds: 15, failureThreshold: 12 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + originals
