// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gitea — a Gitea server (a lightweight, self-hosted Git service with issues, pull
// requests, a package registry and CI via Actions). A plain composable kurly.http
// workload on the official image; with the default SQLite backend its repositories and
// data live on a PersistentVolume, so it needs no external database. Import it, adapt
// with the parameters below, and render with kurly.list:
//
//   local gitea = import 'github.com/metio/kurly/workloads/gitea/server.libsonnet';
//   kurly.list(gitea(rootUrl='https://git.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// SSH: Git-over-SSH runs on container :22, published on the Service beside the HTTP port
// (the 'ssh' port). Route it through a LoadBalancer or NodePort to clone over SSH; HTTP(S)
// Git works without it.
//
// DATABASE: point Gitea at an external PostgreSQL/MySQL through GITEA__database__* env to
// scale past the single SQLite writer. The official image uses s6-overlay, so it runs as
// root and drops to USER_UID/USER_GID.
//
// Single writer: repositories and the SQLite database live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='gitea',
  image='docker.io/gitea/gitea:1.27.0',
  storageSize='20Gi',
  storageClass=null,
  uid=1000,
  gid=1000,
  // The public URL (Gitea builds clone and web links from it).
  rootUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { USER_UID: std.toString(uid), USER_GID: std.toString(gid) }
    + (if rootUrl == null then {} else { GITEA__server__ROOT_URL: rootUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.extraPort('ssh', 22)
  + kurly.env(baseEnv + env)
  // The s6-overlay init needs root and a writable root filesystem; it drops to USER_UID.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/healthz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
