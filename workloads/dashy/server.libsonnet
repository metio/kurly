// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dashy — a Dashy server (a highly customizable, self-hosted dashboard for your
// services). A plain composable kurly.http workload on the official image: its
// configuration lives on a PersistentVolume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local dashy = import 'github.com/metio/kurly/workloads/dashy/server.libsonnet';
//   kurly.list(dashy())
//
// Serves the dashboard on :8080 — compose an exposure onto it. Edit
// /app/user-data/conf.yml on the volume to configure it.
//
// The image rebuilds its assets on a config change and writes across the root
// filesystem, so this relaxes the read-only-rootfs default while keeping non-root,
// dropped capabilities, and no privilege escalation.
//
// Single writer: the configuration lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='dashy',
  image='docker.io/lissy93/dashy:4.4.7',
  storageSize='1Gi',
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
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/user-data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
