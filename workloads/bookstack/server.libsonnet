// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bookstack — a BookStack server (a simple, self-hosted platform for organising and
// storing documentation) on the maintained LinuxServer image, backed by an external
// MySQL/MariaDB, with its config and uploads on a PersistentVolume. Import it, point
// it at a database, and render with kurly.list:
//
//   local bookstack = import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet';
//   kurly.list(bookstack(appUrl='https://docs.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: BookStack needs a MySQL/MariaDB database — the mysql-cluster
// workload provides one. It reads its database coordinates from env and DB_PASS and
// APP_KEY from a provided Secret via envFrom. kurly authors no Secret.
//
// The LinuxServer image runs its s6 init as root and binds :80, so this relaxes
// kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities
// and no privilege escalation.
//
// Single writer: config and uploads live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='bookstack',
  image='lscr.io/linuxserver/bookstack:26.05.2',
  storageSize='5Gi',
  storageClass=null,
  dbHost='bookstack-db',
  dbName='bookstack',
  dbUser='bookstack',
  // The public URL BookStack builds links against (required).
  appUrl=null,
  // The Secret holding DB_PASS and APP_KEY (kurly mints none), via envFrom.
  secretName='bookstack-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_HOST: dbHost,
    DB_PORT: '3306',
    DB_DATABASE: dbName,
    DB_USER: dbUser,
    PUID: '1000',
    PGID: '1000',
  } + (if appUrl == null then {} else { APP_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
