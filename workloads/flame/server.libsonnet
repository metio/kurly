// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// flame — a Flame server (a self-hosted, minimalist start page and application/bookmark
// dashboard for your homelab, with a built-in editor). A plain composable kurly.http
// workload on the official image; its SQLite database lives on a PersistentVolume. Import
// it and render with kurly.list:
//
//   local flame = import 'github.com/metio/kurly/workloads/flame/server.libsonnet';
//   kurly.list(flame())
//
// Serves the dashboard on :5005 — compose an exposure onto it.
//
// PASSWORD: set the admin password through the PASSWORD environment variable (from a
// Secret via kurly.envFromSecret); kurly authors no Secret.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='flame',
  image='docker.io/pawelmalak/flame:2.3.1',
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
  + kurly.port(5005)
  + kurly.servicePort(5005)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
