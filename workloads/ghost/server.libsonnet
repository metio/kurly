// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ghost — a Ghost server (a modern, open-source publishing and newsletter platform).
// A plain composable kurly.http workload on the official image, backed by an external
// MySQL/MariaDB, with its content (themes, images, uploads) on a PersistentVolume.
// Import it, point it at a database, and render with kurly.list:
//
//   local ghost = import 'github.com/metio/kurly/workloads/ghost/server.libsonnet';
//   kurly.list(ghost(url='https://blog.example.com'))
//
// Serves the site and admin on :2368 — compose an exposure onto it.
//
// DATABASE & SECRETS: Ghost needs a MySQL/MariaDB database — the mysql-cluster
// workload provides one. It reads its database coordinates from env and the database
// password from a provided Secret via envFrom. kurly authors no Secret.
//
// Single writer: the content lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='ghost',
  image='docker.io/library/ghost:5.130.6-alpine',
  storageSize='5Gi',
  storageClass=null,
  dbHost='ghost-db',
  dbName='ghost',
  dbUser='ghost',
  // The public URL Ghost builds links against (required).
  url=null,
  // The Secret holding database__connection__password (kurly mints none), via
  // envFrom.
  secretName='ghost-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    database__client: 'mysql',
    database__connection__host: dbHost,
    database__connection__port: '3306',
    database__connection__database: dbName,
    database__connection__user: dbUser,
    NODE_ENV: 'production',
  } + (if url == null then {} else { url: url });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(2368)
  + kurly.servicePort(2368)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/ghost/content', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
