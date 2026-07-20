// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// open-webui — an Open WebUI server (a feature-rich, self-hosted web interface for chatting
// with local and remote LLMs — Ollama and any OpenAI-compatible API — with multi-user
// accounts, RAG and more). A plain composable kurly.http workload on the official image;
// with the default SQLite backend its database and uploads live on a PersistentVolume.
// Import it, adapt with the parameters below, and render with kurly.list:
//
//   local openWebui = import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet';
//   kurly.list(openWebui(ollamaBaseUrl='http://ollama:11434'))
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// SECRET: set WEBUI_SECRET_KEY (session signing) from a Secret via kurly.envFromSecret;
// kurly authors no Secret. Point it at an external PostgreSQL (DATABASE_URL) to scale past
// the single SQLite writer.
//
// Single writer: the SQLite database and uploads live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='open-webui',
  image='ghcr.io/open-webui/open-webui:v0.6.5',
  storageSize='10Gi',
  storageClass=null,
  ollamaBaseUrl=null,
  secretName='open-webui-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if ollamaBaseUrl == null then {} else { OLLAMA_BASE_URL: ollamaBaseUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({ DATA_DIR: '/app/backend/data' } + baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/backend/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
