// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// firefly-iii — a Firefly III server (a free, self-hosted personal-finance manager).
// A plain composable kurly.http workload on the official image, backed by an external
// PostgreSQL, with its uploads and cache on a PersistentVolume. Import it, point it at
// a database, and render with kurly.list:
//
//   local firefly = import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet';
//   kurly.list(firefly(appUrl='https://finance.example.com'))
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: Firefly III reads its database coordinates from env and
// DB_PASSWORD and APP_KEY (a 32-character key) from the environment. The non-secret
// coordinates default to a cnpg-cluster named firefly-iii-db; the secrets come from a
// provided Secret via envFrom. kurly authors no Secret.
//
// The Apache + PHP image starts as root and binds :8080, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: uploads and cache live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='firefly-iii',
  image='docker.io/fireflyiii/core:version-6.6.6',
  storageSize='2Gi',
  storageClass=null,
  dbHost='firefly-iii-db-rw',
  dbName='firefly',
  dbUser='firefly',
  // The public URL Firefly III builds links against (required; also TRUSTED_PROXIES).
  appUrl=null,
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='firefly-iii-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_CONNECTION: 'pgsql',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_DATABASE: dbName,
    DB_USERNAME: dbUser,
    TRUSTED_PROXIES: '**',
  } + (if appUrl == null then {} else { APP_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/storage/upload', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
