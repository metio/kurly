// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// typesense — a Typesense server (a fast, typo-tolerant, self-hosted search engine with a
// clean API, an open alternative to Algolia/Elasticsearch). A plain composable kurly.http
// workload on the official image; its data lives on a PersistentVolume. Import it, point it
// at its API key, and render with kurly.list:
//
//   local typesense = import 'github.com/metio/kurly/workloads/typesense/server.libsonnet';
//   kurly.list(typesense())
//
// Serves the search API on :8108 — usually reached in-cluster (http://typesense:8108), so it
// often needs no exposure.
//
// SECRET: Typesense protects its API with TYPESENSE_API_KEY. kurly authors no Secret;
// provide one holding it, pulled in via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='typesense',
  image='docker.io/typesense/typesense:27.1',
  storageSize='10Gi',
  storageClass=null,
  secretName='typesense-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8108)
  + kurly.servicePort(8108)
  + kurly.envFromSecret(secretName)
  + kurly.env({ TYPESENSE_DATA_DIR: '/data' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
