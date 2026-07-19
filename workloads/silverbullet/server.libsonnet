// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// silverbullet — a SilverBullet server (an extensible, self-hosted markdown
// notebook / personal knowledge base). A plain composable kurly.http workload: your
// notes are plain markdown files on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local silverbullet = import 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet';
//   kurly.list(silverbullet())
//
// Serves the editor on :3000 — compose an exposure onto it.
//
// AUTH: SilverBullet reads SB_USER (user:password) from the environment. kurly
// authors no Secret; provide one holding SB_USER, pulled in via envFrom.
//
// Single writer: the markdown space lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='silverbullet',
  image='ghcr.io/silverbulletmd/silverbullet:2.9.0',
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding SB_USER (kurly mints none), via envFrom.
  secretName='silverbullet-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/space', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/.ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/.ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
