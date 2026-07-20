// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nats — a NATS server (a fast, lightweight, self-hosted messaging system for cloud-native apps:
// pub/sub, request/reply and, with JetStream, persistent streams). A composable kurly.http
// workload used for its Deployment/Service plumbing; NATS speaks its own protocol on :4222 (not
// HTTP), and its JetStream store lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local nats = import 'github.com/metio/kurly/workloads/nats/server.libsonnet';
//   kurly.list(nats())
//
// Serves clients on :4222 — reached in-cluster (nats:4222). The monitoring endpoint on :8222
// is published on the Service beside the client port (the 'monitoring' port).
//
// JetStream is enabled with its store on the volume. This is a single-server NATS (a real
// deployment runs a NATS cluster via a StatefulSet); one writer on a ReadWriteOnce volume, so one
// replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='nats',
  image='docker.io/library/nats:2.10-alpine',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4222)
  + kurly.servicePort(4222)
  + kurly.extraPort('monitoring', 8222)
  + kurly.args(['--jetstream', '--store_dir=/data', '--http_port=8222'])
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
