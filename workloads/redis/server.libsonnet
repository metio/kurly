// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redis — a Redis server (an in-memory data store used as a cache, message broker and database). A plain composable kurly.http workload on the official image
// used for its Deployment/Service plumbing; the server speaks its own wire protocol, not
// HTTP, on :6379, and its data lives on a PersistentVolume. Import it, point it at its
// credentials, and render with kurly.list:
//
//   local redis = import 'github.com/metio/kurly/workloads/redis/server.libsonnet';
//   kurly.list(redis())
//
// Reached in-cluster (redis:6379); it is a single instance, not a replicated cluster —
// for HA use the operator-backed cluster workloads instead where kurly ships one.
//
// SECRET: the credentials are read from the environment on first start. kurly authors no
// Secret; provide one holding them, pulled in via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the store.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='redis',
  image='docker.io/library/redis:7.4.1',
  storageSize='10Gi',
  storageClass=null,
  secretName='redis-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6379)
  + kurly.servicePort(6379)
  + kurly.envFromSecret(secretName)
  + kurly.env({} + env)
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
