// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// qdrant — a Qdrant server (a self-hosted vector database and similarity-search engine for
// embeddings, used to build AI/semantic-search and RAG applications). A plain composable
// kurly.http workload on the official image; its collections live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local qdrant = import 'github.com/metio/kurly/workloads/qdrant/server.libsonnet';
//   kurly.list(qdrant())
//
// Serves the REST API on :6333 — usually reached in-cluster (http://qdrant:6333), so it
// often needs no exposure.
//
// GRPC: Qdrant also serves gRPC on :6334, a separate port this HTTP workload does not
// expose. Add a Service for it (a raw `+` patch) if your clients use gRPC.
//
// Single writer: the collections live on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='qdrant',
  image='docker.io/qdrant/qdrant:v1.13.0',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6333)
  + kurly.servicePort(6333)
  + kurly.env({ QDRANT__STORAGE__STORAGE_PATH: '/qdrant/storage' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/qdrant/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
