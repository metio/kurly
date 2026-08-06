// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mafl — a Mafl server (a minimalistic, configurable homepage for your
// services). A plain composable kurly.http workload on the official image: its
// configuration lives on a PersistentVolume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local mafl = import 'github.com/metio/kurly/workloads/mafl/server.libsonnet';
//   kurly.list(mafl())
//
// Serves the homepage on :3000 — compose an exposure onto it. Edit
// /app/data/config.yml on the volume to configure it; the image seeds a default
// there on first start.
//
// The Nitro server writes nothing outside its data directory and /tmp, so the
// hardened default posture stands whole: non-root, read-only root filesystem,
// dropped capabilities, no privilege escalation.
//
// Single writer: the configuration lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mafl',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + (if env == {} then {} else kurly.env(env))
  // The node user the image ships; fsGroup makes the store writable for it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
