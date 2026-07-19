// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// znc — a ZNC server (an IRC bouncer that stays connected and replays what you
// missed). A plain composable kurly.http workload on the official image: it keeps
// its configuration, module data, and buffers on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local znc = import 'github.com/metio/kurly/workloads/znc/server.libsonnet';
//   kurly.list(znc())
//
// Serves IRC (and the web admin) on :6697 — route it as TCP through a LoadBalancer
// or Gateway TCPRoute.
//
// CONFIGURATION: ZNC needs a znc.conf (with user credentials) at
// /znc-data/configs/znc.conf before it starts. Generate one with `znc --makeconf`
// and place it on the volume, or mount it from a Secret (kurly mints none) — it
// holds passwords.
//
// Single writer: the configuration and buffers live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='znc',
  image='docker.io/library/znc:1.10.2',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6697)
  + kurly.servicePort(6697)
  + (if env == {} then {} else kurly.env(env))
  // The official image runs as uid 1000; pin it and its fsGroup so the data volume
  // is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/znc-data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
