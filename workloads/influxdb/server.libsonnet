// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// influxdb — an InfluxDB 2 server (a self-hosted time-series database for metrics, events
// and IoT data, with a built-in UI, task engine and Flux/InfluxQL query languages). A plain
// composable kurly.http workload on the official image; its data lives on a PersistentVolume.
// Import it, point it at its setup secret, and render with kurly.list:
//
//   local influxdb = import 'github.com/metio/kurly/workloads/influxdb/server.libsonnet';
//   kurly.list(influxdb())
//
// Serves the HTTP API and UI on :8086 — compose an exposure onto it.
//
// SETUP SECRET: on first run InfluxDB provisions itself from DOCKER_INFLUXDB_INIT_USERNAME,
// DOCKER_INFLUXDB_INIT_PASSWORD, DOCKER_INFLUXDB_INIT_ORG and DOCKER_INFLUXDB_INIT_BUCKET.
// kurly authors no Secret; provide one holding them, pulled in via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='influxdb',
  image='docker.io/library/influxdb:2.7.11',
  storageSize='20Gi',
  storageClass=null,
  secretName='influxdb-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8086)
  + kurly.servicePort(8086)
  + kurly.envFromSecret(secretName)
  + kurly.env({ DOCKER_INFLUXDB_INIT_MODE: 'setup' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/influxdb2', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
