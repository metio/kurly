// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// clickhouse — a ClickHouse server (a fast, self-hosted column-oriented SQL database for
// real-time analytics over very large datasets). A plain composable kurly.http workload on
// the official single-node image; its data lives on a PersistentVolume. Import it, point it
// at its credentials, and render with kurly.list:
//
//   local clickhouse = import 'github.com/metio/kurly/workloads/clickhouse/server.libsonnet';
//   kurly.list(clickhouse())
//
// Serves the HTTP API on :8123 — usually reached in-cluster (http://clickhouse:8123). The
// native protocol on :9000 is published on the Service beside it (the 'native' port).
//
// SECRET: ClickHouse reads CLICKHOUSE_USER, CLICKHOUSE_PASSWORD and CLICKHOUSE_DB from the
// environment on first start. kurly authors no Secret; provide one holding them, via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='clickhouse',
  image='docker.io/clickhouse/clickhouse-server:24.8',
  storageSize='20Gi',
  storageClass=null,
  secretName='clickhouse-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8123)
  + kurly.servicePort(8123)
  + kurly.extraPort('native', 9000)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(101, gid=101, fsGroup=101)
  + kurly.store('/var/lib/clickhouse', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
