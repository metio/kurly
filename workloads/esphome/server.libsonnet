// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// esphome — an ESPHome dashboard server (the web dashboard and compiler for ESPHome: create
// and flash firmware for ESP8266/ESP32 smart-home devices from YAML). A plain composable
// kurly.http workload on the official image; its device configurations and build artifacts
// live on a PersistentVolume. Import it and render with kurly.list:
//
//   local esphome = import 'github.com/metio/kurly/workloads/esphome/server.libsonnet';
//   kurly.list(esphome())
//
// Serves the dashboard on :6052 — compose an exposure onto it.
//
// The dashboard runs as root to compile firmware and manage its config tree, with a writable
// root filesystem. Over-the-air flashing works over the network; USB flashing needs a device
// this workload does not mount.
//
// Single writer: the configs and builds live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='esphome',
  image='ghcr.io/esphome/esphome:2025.7.3',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6052)
  + kurly.servicePort(6052)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
