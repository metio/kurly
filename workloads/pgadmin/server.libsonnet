// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pgadmin — a pgAdmin 4 server (the web UI for administering PostgreSQL: browse schemas,
// run queries and manage servers from the browser). A plain composable kurly.http workload
// on the official image; its session and configuration store (SQLite) lives on a
// PersistentVolume. Import it, point it at its login secret, and render with kurly.list:
//
//   local pgadmin = import 'github.com/metio/kurly/workloads/pgadmin/server.libsonnet';
//   kurly.list(pgadmin())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// SECRETS: pgAdmin needs PGADMIN_DEFAULT_EMAIL and PGADMIN_DEFAULT_PASSWORD for the initial
// login. kurly authors no Secret; provide one holding them, pulled in via envFrom.
//
// The image runs as the pgadmin user (uid 5050), which must own the config volume.
//
// Single writer: the config store lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pgadmin',
  image='docker.io/dpage/pgadmin4:9.8',
  storageSize='1Gi',
  storageClass=null,
  secretName='pgadmin-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(5050, gid=5050, fsGroup=5050)
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/pgadmin', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/misc/ping', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
