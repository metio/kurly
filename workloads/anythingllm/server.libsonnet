// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// anythingllm — an AnythingLLM server (a self-hosted, all-in-one AI application: chat with your
// documents through RAG, agents and many LLM/embedding providers). A plain composable kurly.http
// workload on the official image; its storage (the embedded vector database, uploaded documents,
// settings) lives on a PersistentVolume under /app/server/storage. Import it and render with
// kurly.list:
//
//   local anythingllm = import 'github.com/metio/kurly/workloads/anythingllm/server.libsonnet';
//   kurly.list(anythingllm())
//
// Serves the web app and API on :3001 — compose an exposure onto it.
//
// PROVIDERS & SECRETS: point it at your LLM and embedding providers with the documented
// environment variables. kurly authors no Secret; pass non-secret settings via env, and provide
// API keys through a Secret referenced with your own envFrom (compose kurly.envFromSecret on).
//
// Single writer: the storage is a ReadWriteOnce volume, so one replica, recreated (never rolled)
// to keep two pods off the same storage directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='anythingllm',
  image='docker.io/mintplexlabs/anythingllm:latest@sha256:9a87bca983e688db2a11a0ed3290daa16c4b67556617ae77325c9d12c6a37c25',
  storageSize='10Gi',
  storageClass=null,
  env={ STORAGE_DIR: '/app/server/storage' },
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3001)
  + kurly.servicePort(3001)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/server/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
