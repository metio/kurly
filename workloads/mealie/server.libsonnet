// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mealie — a Mealie server (a self-hosted recipe manager and meal planner with a recipe
// scraper, shopping lists and a REST API). A plain composable kurly.http workload on the
// official image; with the default SQLite backend its database and uploaded assets live
// on a PersistentVolume. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local mealie = import 'github.com/metio/kurly/workloads/mealie/server.libsonnet';
//   kurly.list(mealie(baseUrl='https://recipes.example.com'))
//
// Serves the web app and API on :9000 — compose an exposure onto it.
//
// DATABASE: point Mealie at an external PostgreSQL (DB_ENGINE=postgres plus the
// POSTGRES_* connection, from a Secret via kurly.envFromSecret) to scale past the single
// SQLite writer.
//
// Single writer: the SQLite database and assets live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='mealie',
  image='ghcr.io/mealie-recipes/mealie:v3.20.1',
  storageSize='5Gi',
  storageClass=null,
  // The public URL (Mealie builds absolute links from it).
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.env({ DATA_DIR: '/app/data' } + baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/app/about', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
