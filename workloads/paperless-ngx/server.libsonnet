// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// paperless-ngx — a Paperless-ngx server (scan, index, and archive your documents
// with OCR and full-text search). A plain composable kurly.http workload backed by
// an external PostgreSQL and Redis, with its data, media, consume, and export
// trees on a PersistentVolume. Import it, point it at a database and cache, and
// render with kurly.list:
//
//   local paperless = import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet';
//   kurly.list(paperless(url='https://paperless.example.com'))
//
// Serves the web UI and API on :8000 — compose an exposure onto it. The image runs
// the web server and its Celery workers together, so one deployment is the whole
// app.
//
// DATABASE, CACHE & SECRETS: Paperless reads its database and Redis coordinates
// and its secrets from the environment. The non-secret coordinates default to a
// cnpg-cluster named paperless-db and a valkey named paperless-cache; the sensitive
// values (PAPERLESS_DBPASS, PAPERLESS_SECRET_KEY, and the first-run admin password)
// come from a provided Secret via envFrom. kurly authors no Secret.
//
// The entrypoint and Celery workers write to the root filesystem, so this relaxes
// the read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Single writer: the document archive lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='paperless-ngx',
  image='ghcr.io/paperless-ngx/paperless-ngx:2.20.15',
  storageSize='20Gi',
  storageClass=null,
  dbHost='paperless-db-rw',
  dbName='paperless',
  dbUser='paperless',
  redisHost='paperless-cache',
  // The public URL Paperless builds links against (PAPERLESS_URL).
  url=null,
  // The first-run admin username (its password comes from the Secret).
  adminUser='admin',
  // The Secret holding PAPERLESS_DBPASS, PAPERLESS_SECRET_KEY, and
  // PAPERLESS_ADMIN_PASSWORD (kurly mints none), via envFrom.
  secretName='paperless-ngx-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    PAPERLESS_DBHOST: dbHost,
    PAPERLESS_DBPORT: '5432',
    PAPERLESS_DBNAME: dbName,
    PAPERLESS_DBUSER: dbUser,
    PAPERLESS_REDIS: 'redis://' + redisHost + ':6379',
    PAPERLESS_ADMIN_USER: adminUser,
    PAPERLESS_DATA_DIR: '/usr/src/paperless/data',
    PAPERLESS_MEDIA_ROOT: '/usr/src/paperless/media',
    PAPERLESS_CONSUMPTION_DIR: '/usr/src/paperless/consume',
    PAPERLESS_EXPORT_DIR: '/usr/src/paperless/export',
  } + (if url == null then {} else { PAPERLESS_URL: url });

  // Paperless keeps four trees under /usr/src/paperless; surface media, consume,
  // and export as subpaths of the same volume (data is the store's own mount).
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/usr/src/paperless/media', subPath: 'media' },
          { name: 'store', mountPath: '/usr/src/paperless/consume', subPath: 'consume' },
          { name: 'store', mountPath: '/usr/src/paperless/export', subPath: 'export' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/usr/src/paperless/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
