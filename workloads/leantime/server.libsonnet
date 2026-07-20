// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// leantime — a Leantime server (a self-hosted, open-source project-management system for
// non-project-managers: goals, ideas, tasks, time tracking). A plain composable kurly.http workload
// on the official image, backed by an external MySQL/MariaDB; uploaded files live on a
// PersistentVolume under /var/www/html/userfiles. Import it, point it at its backend, and render
// with kurly.list:
//
//   local leantime = import 'github.com/metio/kurly/workloads/leantime/server.libsonnet';
//   kurly.list(leantime())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Leantime reads LEAN_DB_HOST, LEAN_DB_DATABASE, LEAN_DB_USER, LEAN_DB_PASSWORD
// and LEAN_SESSION_PASSWORD from the environment. kurly authors no Secret; provide one holding
// them, via envFrom. Pair it with a MySQL/MariaDB you run separately.
//
// Single writer for uploads: the userfiles volume is ReadWriteOnce, so one replica, recreated
// (never rolled) to keep two pods off the same directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='leantime',
  image='docker.io/leantime/leantime:latest@sha256:6150dd3e8a1e17f1ead8d462d31e26177fe906ce3602dbbbf6af5417ef809de3',
  storageSize='5Gi',
  storageClass=null,
  secretName='leantime-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/userfiles', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
