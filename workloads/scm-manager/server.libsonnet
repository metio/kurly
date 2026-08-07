// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// scm-manager — an SCM-Manager server (shares and manages Git, Mercurial and
// Subversion repositories over HTTP, with users, groups and permissions in one
// place). A plain composable kurly.http workload: every repository, plugin and
// setting lives in SCM_HOME on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local scmmanager = import 'github.com/metio/kurly/workloads/scm-manager/server.libsonnet';
//   kurly.list(scmmanager())
//
// Serves the web UI, the REST API and the repository protocols on :8080 —
// compose an exposure onto it. Git, Mercurial and Subversion all speak over that
// same HTTP port, so nothing else has to be published.
//
// The FIRST START asks for an administrator account through the setup screen and
// leaves the instance open until somebody completes it, so finish the setup
// before the instance is reachable from anywhere you do not control.
//
// Single writer: the repositories live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two servers writing the same repository directory is
// not something git, hg or svn will sort out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='scm-manager',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '2Gi' } },
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
  // The image ships the server as uid 1000 in the root group, and SCM_HOME is
  // group-writable, so the volume is reachable without relaxing anything.
  + kurly.runAs(1000, gid=0, fsGroup=0)
  // The server unpacks plugins and the web application into CACHE_DIR and the JVM
  // writes its own temporary files, both beside the read-only install tree.
  + kurly.scratch('/var/cache/scm/work')
  + kurly.scratch('/tmp')
  + kurly.store('/var/lib/scm', storageSize, storageClass=storageClass)
  // A JVM that relinks its plugins on first boot takes minutes; probe by
  // connection, because every HTTP path either redirects into the setup screen or
  // answers 401 until an administrator exists.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
