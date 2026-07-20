// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// penpot (backend) — the Penpot backend: the API and data layer of Penpot, the self-hosted,
// open-source design and prototyping platform (an alternative to Figma). Penpot runs as THREE
// workloads — this backend, a frontend that serves the app and proxies to it, and an exporter —
// backed by an external PostgreSQL and Redis. Import it, point it at its backends, and render
// with kurly.list:
//
//   local backend = import 'github.com/metio/kurly/workloads/penpot/backend.libsonnet';
//   kurly.list(backend())
//
// Serves the API on :6060 — the frontend reaches it at http://penpot-backend:6060.
//
// BACKENDS & SECRETS: the backend reads its PostgreSQL and Redis connection (PENPOT_DATABASE_URI,
// PENPOT_REDIS_URI) and PENPOT_SECRET_KEY from the environment. kurly authors no Secret; provide
// one holding them, via envFrom. All three Penpot stages share it. Pairs with a cnpg-cluster
// named penpot-db and a Redis.
//
// Single writer: uploaded assets live on a ReadWriteOnce volume, so one replica, recreated (put
// PENPOT_ASSETS_STORAGE_BACKEND on S3 to scale out).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='penpot-backend',
  image='docker.io/penpotapp/backend:2.3.2',
  storageSize='20Gi',
  storageClass=null,
  publicUri=null,
  secretName='penpot-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if publicUri == null then {} else { PENPOT_PUBLIC_URI: publicUri };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6060)
  + kurly.servicePort(6060)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
