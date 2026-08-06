// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wiki-go — a Wiki-Go server (a flat-file wiki written in Go: pages are Markdown
// files on disk, there is no database at all). A plain composable kurly.http
// workload; the pages, uploads and the wiki's own config.yaml live together on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local wikigo = import 'github.com/metio/kurly/workloads/wiki-go/server.libsonnet';
//   kurly.list(wikigo())
//
// Serves the wiki on :8080 — compose an exposure onto it.
//
// IT SHIPS A DEFAULT ADMINISTRATOR. Wiki-Go writes its configuration on first
// start with a known admin account, so an instance reachable from the internet is
// administrable by anyone who read the documentation. Change that account before
// exposing it.
//
// Single writer: one directory tree on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wiki-go',
  image=defaultImage,
  // Pages, uploaded files and the generated data/config.yaml.
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
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
  // A static Go binary run from its working directory /wiki. The image declares
  // uid 1000, but the mounted volume arrives owned by root — pin the uid and its
  // fsGroup so the wiki can write its own pages back.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/wiki/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  // Probe by connection: the wiki answers / with a redirect to its login page
  // once anonymous reading is turned off, and a probe that follows it into an
  // authenticated page would kill a perfectly healthy pod.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
