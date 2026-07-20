// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redmine — a Redmine server (a mature, self-hosted project-management web app: issue
// tracking, wikis, forums, Gantt charts and time tracking). A plain composable kurly.http
// workload on the official image, backed by an external MySQL/MariaDB or PostgreSQL, with
// its uploaded files on a PersistentVolume. Import it, point it at a database, and render
// with kurly.list:
//
//   local redmine = import 'github.com/metio/kurly/workloads/redmine/server.libsonnet';
//   kurly.list(redmine())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Redmine reads its database connection (REDMINE_DB_* or DATABASE_URL)
// and REDMINE_SECRET_KEY_BASE from the environment. kurly authors no Secret; provide one
// holding them, pulled in via envFrom. Pairs with a mysql-cluster named redmine-db.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='redmine',
  image='docker.io/library/redmine:6.0.5',
  storageSize='10Gi',
  storageClass=null,
  secretName='redmine-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/usr/src/redmine/files', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
