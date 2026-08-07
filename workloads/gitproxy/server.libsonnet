// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gitproxy — a FINOS Git Proxy server (it sits between a developer and an upstream
// git host, holds every outgoing push, applies rules to it and releases it only
// once somebody has approved). A plain composable kurly.http workload: the
// approval records and the held pushes live on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local gitproxy = import 'github.com/metio/kurly/workloads/gitproxy/server.libsonnet';
//   kurly.list(gitproxy())
//
// TWO PORTS, and they are used by different people. :8080 is the web UI and the
// API — that is the one to compose an exposure onto. :8000 is the git endpoint a
// developer sets as their push remote, published on the Service beside it as the
// 'git' port; route it wherever the developers are.
//
// IT SHIPS WITH A PUBLISHED COOKIE SECRET AND A DEFAULT ADMIN ACCOUNT. The
// configuration baked into the image is the project's example one, cookie secret
// and all, and the local authentication backend creates the well-known
// admin/admin account on first start. Change the password and supply your own
// configuration before anyone can reach it.
//
// Single writer: the file-backed database and the held pushes are on a
// ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gitproxy',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('git', 8000)
  + kurly.env(env)
  // The image already runs as an unprivileged account, so the hardened posture
  // stands — except for the root filesystem: the entrypoint writes the UI's
  // runtime configuration into the built asset directory it also serves from, and
  // the proxy clones each held push into its own tree beside it. Neither path can
  // be an emptyDir without hiding the files that ship there.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/.data', storageSize, storageClass=storageClass)
  // Probe the UI port by connection: the single-page app answers the root with a
  // redirect to its login route, which a path probe would follow into an answer
  // that says nothing about the server being up.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
