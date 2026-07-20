// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// home-assistant — a Home Assistant server (Home Assistant Core: the leading self-hosted
// home-automation platform, integrating thousands of smart-home devices and services behind
// one dashboard and automation engine). A plain composable kurly.http workload on the
// official image; its configuration and state database live on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local homeAssistant = import 'github.com/metio/kurly/workloads/home-assistant/server.libsonnet';
//   kurly.list(homeAssistant())
//
// Serves the dashboard on :8123 — compose an exposure onto it.
//
// Home Assistant expects to run as root and write its whole /config tree, so it uses a
// writable root filesystem. Local-network device discovery (mDNS, SSDP) does not work through
// a ClusterIP; devices reachable by IP, MQTT or cloud integrations work normally. USB radios
// need a device this workload does not mount — use a network-attached coordinator instead.
//
// Single writer: the config and database live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='home-assistant',
  image='ghcr.io/home-assistant/home-assistant:2025.7',
  storageSize='10Gi',
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
  + kurly.port(8123)
  + kurly.servicePort(8123)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
