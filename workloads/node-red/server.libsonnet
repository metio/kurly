// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// node-red — a Node-RED server (a flow-based, low-code programming tool for wiring together
// APIs, devices and online services in a browser editor; popular for home automation and
// event-driven glue). A plain composable kurly.http workload on the official image; its
// flows and settings live on a PersistentVolume. Import it and render with kurly.list:
//
//   local nodeRed = import 'github.com/metio/kurly/workloads/node-red/server.libsonnet';
//   kurly.list(nodeRed())
//
// Serves the editor and HTTP endpoints on :1880 — compose an exposure onto it.
//
// Single writer: the flows live on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='node-red',
  image='docker.io/nodered/node-red:4.0.9',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(1880)
  + kurly.servicePort(1880)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
