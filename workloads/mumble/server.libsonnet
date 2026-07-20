// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mumble — a Mumble server (Murmur: a self-hosted, low-latency voice-chat server for gaming
// and communities). A composable kurly.http workload used here for its Deployment and
// Service plumbing, but Mumble speaks its own voice protocol, not HTTP: it listens on
// :64738 (TCP for control, UDP for voice), and its SQLite database lives on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local mumble = import 'github.com/metio/kurly/workloads/mumble/server.libsonnet';
//   kurly.list(mumble())
//
// The Service publishes the TCP control port. UDP voice on the same port number needs a
// second Service (a raw `+` patch, usually a LoadBalancer) — clients can fall back to TCP,
// but UDP is strongly preferred for latency. Expose it to your clients (often a
// LoadBalancer) rather than an HTTP ingress.
//
// SECRET: set the SuperUser password through MUMBLE_SUPERUSER_PASSWORD from a Secret via
// kurly.envFromSecret; kurly authors no Secret.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mumble',
  image='docker.io/mumblevoip/mumble-server:v1.5.735-0',
  storageSize='1Gi',
  storageClass=null,
  secretName='mumble-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(64738)
  + kurly.servicePort(64738)
  + kurly.extraPort('voice-udp', 64738, protocol='UDP')
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
