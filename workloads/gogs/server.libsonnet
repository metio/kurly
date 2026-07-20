// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gogs — a Gogs server (a painless, self-hosted Git service: a lightweight, fast Git
// server with a clean web UI). A plain composable kurly.http workload on the official
// image; with the default SQLite backend its repositories and data live on a
// PersistentVolume, so it needs no external database. Import it, adapt with the
// parameters below, and render with kurly.list:
//
//   local gogs = import 'github.com/metio/kurly/workloads/gogs/server.libsonnet';
//   kurly.list(gogs())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// SSH: Git-over-SSH runs on container :22, published on the Service beside the HTTP port
// (the 'ssh' port). Route it through a LoadBalancer or NodePort to clone over SSH; HTTP(S)
// Git works without it.
//
// Single writer: repositories and the SQLite database live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='gogs',
  image='docker.io/gogs/gogs:0.14.3',
  storageSize='20Gi',
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
  + kurly.extraPort('ssh', 22)
  + kurly.env(env)
  // The image runs its init as root and serves as the git user; the root filesystem
  // stays writable for its runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
