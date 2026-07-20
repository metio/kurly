// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openobserve — an OpenObserve server (a self-hosted, high-performance observability
// platform for logs, metrics and traces, a lightweight alternative to Elasticsearch/Splunk).
// A plain composable kurly.http workload on the official image; with local disk storage its
// data lives on a PersistentVolume. Import it, point it at its admin secret, and render with
// kurly.list:
//
//   local openobserve = import 'github.com/metio/kurly/workloads/openobserve/server.libsonnet';
//   kurly.list(openobserve())
//
// Serves the web UI and ingestion API on :5080 — compose an exposure onto it.
//
// SECRET: OpenObserve needs ZO_ROOT_USER_EMAIL and ZO_ROOT_USER_PASSWORD for the initial
// admin. kurly authors no Secret; provide one holding them, pulled in via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='openobserve',
  image='docker.io/openobserve/openobserve:v0.14.4',
  storageSize='20Gi',
  storageClass=null,
  secretName='openobserve-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5080)
  + kurly.servicePort(5080)
  + kurly.envFromSecret(secretName)
  + kurly.env({ ZO_DATA_DIR: '/data' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
