// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// otterwiki — an Otter Wiki server (a small wiki written in Markdown, where every
// page is a file in a git repository and every edit is a commit). A plain
// composable kurly.http workload: the repository and its index live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local otterwiki = import 'github.com/metio/kurly/workloads/otterwiki/server.libsonnet';
//   kurly.list(otterwiki())
//
// Serves the wiki on :80 — compose an exposure onto it.
//
// IT IS PUBLICLY READABLE AND WRITABLE UNTIL YOU CONFIGURE OTHERWISE. Otter Wiki
// starts with anonymous read and write, and the first account you register becomes
// the administrator — so on an exposed instance that is whoever arrives first. Set
// the permissions from its own settings page before publishing it, or put an
// authenticating proxy in front.
//
// Single writer: one git repository on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two pods committing to the same repository is not a
// thing git will sort out for you.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='otterwiki',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  // supervisord runs nginx and the application together and drops privileges to
  // their accounts, which it can only do from root — the same shape as matchering
  // here. It also binds :80, which an unprivileged process may not.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx and supervisord write their pid, logs and temporary bodies inside the
  // image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/app-data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
