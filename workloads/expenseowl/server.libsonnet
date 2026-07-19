// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// expenseowl — an ExpenseOwl server (a simple, self-hosted expense tracker). A
// plain composable kurly.http workload: it keeps its expenses in a file-backed
// store on a PersistentVolume, so it needs no external database. Import it and
// render with kurly.list:
//
//   local expenseowl = import 'github.com/metio/kurly/workloads/expenseowl/server.libsonnet';
//   kurly.list(expenseowl())
//
// Serves the web UI and API on :8080 — compose an exposure onto it.
//
// Single writer: one file-backed store on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='expenseowl',
  image='ghcr.io/tanq16/expenseowl:v4.1',
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
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  // A static Go binary, uid-agnostic; pin a non-root uid and its fsGroup so the
  // data volume is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
