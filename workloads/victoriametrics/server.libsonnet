// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// victoriametrics — a VictoriaMetrics server (a fast, cost-effective, self-hosted
// time-series database and Prometheus-compatible monitoring backend). A plain composable
// kurly.http workload on the official single-node image; its data lives on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local victoriametrics = import 'github.com/metio/kurly/workloads/victoriametrics/server.libsonnet';
//   kurly.list(victoriametrics())
//
// Serves the HTTP API (ingestion, PromQL, UI) on :8428 — compose an exposure onto it.
//
// Single writer: the time-series data lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='victoriametrics',
  image='docker.io/victoriametrics/victoria-metrics:v1.109.0',
  storageSize='20Gi',
  storageClass=null,
  retentionPeriod='1',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8428)
  + kurly.servicePort(8428)
  + kurly.args(['--storageDataPath=/victoria-metrics-data', '--retentionPeriod=' + retentionPeriod])
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/victoria-metrics-data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
