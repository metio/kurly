// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ollama — an Ollama server (a self-hosted runtime for running large language models locally,
// with a simple REST API; the backend Open WebUI and many AI apps talk to). A plain composable
// kurly.http workload on the official image; its downloaded models live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local ollama = import 'github.com/metio/kurly/workloads/ollama/server.libsonnet';
//   kurly.list(ollama())
//
// Serves the API on :11434 — usually reached in-cluster (http://ollama:11434), e.g. from
// open-webui.
//
// GPU: Ollama runs on CPU by default. For acceleration, schedule it on a GPU node and request
// the vendor's device resource (compose nodeSelector/tolerations and resources onto it).
//
// Single writer: the models live on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the store.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='ollama',
  image='docker.io/ollama/ollama:0.5.4',
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '8Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(11434)
  + kurly.servicePort(11434)
  + kurly.env({ OLLAMA_MODELS: '/models', OLLAMA_HOST: '0.0.0.0:11434' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/models', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
