// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// meilisearch — a Meilisearch server (a fast, typo-tolerant, self-hosted search engine with
// a simple REST API, an open alternative to Algolia). A plain composable kurly.http workload
// on the official image; its indexes live on a PersistentVolume. It is the search companion
// several apps expect (e.g. karakeep). Import it, point it at its key, and render with
// kurly.list:
//
//   local meilisearch = import 'github.com/metio/kurly/workloads/meilisearch/server.libsonnet';
//   kurly.list(meilisearch())
//
// Serves the search API on :7700 — usually reached in-cluster (http://meilisearch:7700), so
// it often needs no exposure.
//
// SECRET: Meilisearch protects its API with MEILI_MASTER_KEY. kurly authors no Secret;
// provide one holding it, pulled in via envFrom.
//
// Single writer: the indexes live on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='meilisearch',
  image='docker.io/getmeili/meilisearch:v1.12.0',
  storageSize='10Gi',
  storageClass=null,
  secretName='meilisearch-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7700)
  + kurly.servicePort(7700)
  + kurly.envFromSecret(secretName)
  + kurly.env({ MEILI_ENV: 'production', MEILI_DB_PATH: '/meili_data' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/meili_data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
