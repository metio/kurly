// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docmost — a Docmost server (a self-hosted, open-source collaborative wiki and
// documentation platform). A plain composable kurly.http workload on the official
// image, backed by an external PostgreSQL and Redis, with its attachments on a
// PersistentVolume. Import it, point it at its backends, and render with kurly.list:
//
//   local docmost = import 'github.com/metio/kurly/workloads/docmost/server.libsonnet';
//   kurly.list(docmost(appUrl='https://wiki.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Docmost reads DATABASE_URL, REDIS_URL and APP_SECRET from the
// environment. kurly authors no Secret; provide one holding all three, pulled in via
// envFrom. The defaults pair with a cnpg-cluster named docmost-db and a Redis.
//
// Single writer: local attachment storage lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files. Point STORAGE_DRIVER
// at S3 to scale past the single writer.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='docmost',
  image='docker.io/docmost/docmost:0.95.0',
  storageSize='10Gi',
  storageClass=null,
  // The public URL.
  appUrl=null,
  // The Secret holding DATABASE_URL, REDIS_URL and APP_SECRET (kurly mints none),
  // via envFrom.
  secretName='docmost-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if appUrl == null then {} else { APP_URL: appUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + { STORAGE_DRIVER: 'local', FILE_UPLOAD_SIZE_LIMIT: '50mb' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
