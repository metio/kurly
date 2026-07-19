// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// inspircd — an InspIRCd server (a modular IRC daemon). A plain composable
// kurly.http workload on the official image: it keeps its runtime data (logs, TLS
// material) on a PersistentVolume and reads its configuration from a mounted
// config. Import it and render with kurly.list:
//
//   local inspircd = import 'github.com/metio/kurly/workloads/inspircd/server.libsonnet';
//   kurly.list(inspircd())
//
// Serves IRC-over-TLS on :6697 — route it as TCP through a LoadBalancer or Gateway
// TCPRoute.
//
// CONFIGURATION: InspIRCd needs its configuration at /inspircd/conf (an
// inspircd.conf and the files it includes). Mount it with kurly.config, or from a
// Secret (kurly mints none) where it carries oper passwords or link credentials.
//
// Single writer: the runtime data lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='inspircd',
  image='docker.io/inspircd/inspircd-docker:4.11.0',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
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
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/inspircd/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
