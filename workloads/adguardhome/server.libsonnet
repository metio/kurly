// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// adguardhome — an AdGuard Home server (a self-hosted, network-wide DNS ad- and
// tracker-blocker with a friendly web UI, an alternative to Pi-hole). A plain composable
// kurly.http workload on the official image; its configuration and runtime data (config,
// query log, statistics) live on a PersistentVolume. Import it and render with kurly.list:
//
//   local adguardhome = import 'github.com/metio/kurly/workloads/adguardhome/server.libsonnet';
//   kurly.list(adguardhome())
//
// Serves the admin UI on :3000 (the first-run setup wizard) — compose an exposure onto it.
//
// DNS: AdGuard Home answers DNS on :53 (TCP and UDP), separate ports this HTTP workload
// does not expose. Add a Service for :53 (usually a LoadBalancer so clients can point their
// resolver at it) — a raw `+` patch; the admin UI works without it.
//
// The AdGuardHome.yaml config and the work directory both live under /opt/adguardhome, so a
// single volume mounted there persists everything. The process binds the privileged DNS
// port, so it runs as root with a writable root filesystem.
//
// Single writer: the config and data live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='adguardhome',
  image='docker.io/adguard/adguardhome:v0.107.65',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  // AdGuard Home binds the privileged DNS port, so it needs root and a writable root
  // filesystem alongside its data volume.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/adguardhome', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
