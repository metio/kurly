// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// emqx — an EMQX server (a highly-scalable, self-hosted MQTT broker for IoT, with a web
// dashboard, rules engine and clustering). A composable kurly.http workload used for its
// Deployment/Service plumbing; EMQX speaks MQTT on :1883 (not HTTP) and keeps its data on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local emqx = import 'github.com/metio/kurly/workloads/emqx/server.libsonnet';
//   kurly.list(emqx())
//
// Serves MQTT on :1883 — reached in-cluster (emqx:1883) or exposed to devices (often a
// LoadBalancer). The other default listeners ride onto the Service beside it: MQTT-over-WebSocket
// on :8083 ('ws'), its TLS forms on :8084 ('wss') and :8883 ('mqtts'), and the web dashboard on
// :18083 ('dashboard').
//
// Single node: this is a single-instance EMQX, not a cluster (EMQX clusters via a StatefulSet
// and peer discovery). Single writer on a ReadWriteOnce volume: one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='emqx',
  image='docker.io/emqx/emqx:5.8.0',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(1883)
  + kurly.servicePort(1883)
  + kurly.extraPort('dashboard', 18083)
  + kurly.extraPort('ws', 8083)
  + kurly.extraPort('wss', 8084)
  + kurly.extraPort('mqtts', 8883)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/opt/emqx/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
