// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mongo — a MongoDB server (a self-hosted, document-oriented NoSQL database). A plain composable kurly.http workload on the official image
// used for its Deployment/Service plumbing; the server speaks its own wire protocol, not
// HTTP, on :27017, and its data lives on a PersistentVolume. Import it, point it at its
// credentials, and render with kurly.list:
//
//   local mongo = import 'github.com/metio/kurly/workloads/mongo/server.libsonnet';
//   kurly.list(mongo())
//
// Reached in-cluster (mongo:27017); it is a single instance, not a replicated cluster —
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
  name='mongo',
  image='docker.io/library/mongo:8.0.3',
  storageSize='10Gi',
  storageClass=null,
  secretName='mongo-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(27017)
  + kurly.servicePort(27017)
  + kurly.envFromSecret(secretName)
  + kurly.env({} + env)
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.store('/data/db', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
