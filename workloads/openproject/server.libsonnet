// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openproject — an OpenProject server (a self-hosted, open-source project-management and
// collaboration suite: work packages, Gantt charts, agile boards, wikis and time tracking). A
// plain composable kurly.http workload on the official image, backed by an external PostgreSQL,
// with its uploaded assets on a PersistentVolume. Import it, point it at a database, and render
// with kurly.list:
//
//   local openproject = import 'github.com/metio/kurly/workloads/openproject/server.libsonnet';
//   kurly.list(openproject(hostName='projects.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: OpenProject reads DATABASE_URL, SECRET_KEY_BASE and its host settings
// from the environment. kurly authors no Secret; provide one holding them, via envFrom. Pairs
// with a cnpg-cluster named openproject-db. A production deployment also wants a memcached and,
// for large instances, background-worker replicas.
//
// Single writer: uploaded assets live on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='openproject',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  hostName=null,
  secretName='openproject',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { RAILS_MIN_THREADS: '4', RAILS_MAX_THREADS: '16' }
    + (if hostName == null then {} else { OPENPROJECT_HOST__NAME: hostName });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The all-in-one image's entrypoint switches users with su while it prepares the
  // application, which needs root and the SETUID/SETGID capabilities.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/openproject/assets', storageSize, storageClass=storageClass)
  // The first start migrates the schema and precompiles assets before Rails binds,
  // which takes many minutes.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15, failureThreshold: 80 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
