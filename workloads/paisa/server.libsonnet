// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// paisa — a Paisa server (a plain-text, double-entry personal finance manager
// built on ledger/beancount journals). A plain composable kurly.http workload: it
// reads its configuration and journal from a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local paisa = import 'github.com/metio/kurly/workloads/paisa/server.libsonnet';
//   kurly.list(paisa())
//
// Serves the web UI on :7500 — compose an exposure onto it.
//
// DATA: Paisa reads paisa.yaml and the journal it references from its working
// directory (/data here). Provide them on the volume before first use.
//
// Single writer: the journal and its generated database live on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='paisa',
  image='ghcr.io/ananthakumaran/paisa:0.7.4',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  // Run Paisa from the data volume so it finds paisa.yaml and the journal there.
  local workdir = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [container { workingDir: '/data' } for container in super.containers],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7500)
  + kurly.servicePort(7500)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + workdir
