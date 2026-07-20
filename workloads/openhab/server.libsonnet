// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openhab — an openHAB server (a vendor-neutral, self-hosted home-automation platform that
// integrates a huge range of devices and technologies behind one engine, UI and rule system). A
// plain composable kurly.http workload on the official image; its three persistent directories —
// configuration, runtime userdata, and installed add-ons — each get their own PersistentVolume.
// Import it and render with kurly.list:
//
//   local openhab = import 'github.com/metio/kurly/workloads/openhab/server.libsonnet';
//   kurly.list(openhab())
//
// Serves the web UI on :8080 — compose an exposure onto it.
//
// STORAGE: openHAB keeps its config at /openhab/conf, its runtime state and database at
// /openhab/userdata, and installed bindings at /openhab/addons, so this composes kurly.store
// three times, one PVC each. Devices on the local network work; USB/serial radios are hardware
// and are not modelled here (use a network-attached coordinator).
//
// Single writer: the data lives on ReadWriteOnce volumes, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='openhab',
  image='docker.io/openhab/openhab:4.3.0',
  confSize='2Gi',
  userdataSize='5Gi',
  addonsSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  + kurly.runAs(9001, gid=9001, fsGroup=9001)
  + kurly.writableRootFilesystem()
  // Three distinct PVCs: configuration, runtime userdata, and installed add-ons.
  + kurly.store('/openhab/conf', confSize, storageClass=storageClass)
  + kurly.store('/openhab/userdata', userdataSize, storageClass=storageClass)
  + kurly.store('/openhab/addons', addonsSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
