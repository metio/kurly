// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// audiobookshelf — an Audiobookshelf server (a self-hosted audiobook and podcast
// server). A plain composable kurly.http workload on the official image: it keeps
// its config, metadata, and library on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local audiobookshelf = import 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet';
//   kurly.list(audiobookshelf())
//
// Serves the web UI and API on :80 — compose an exposure onto it. Put your
// audiobooks and podcasts under /audiobooks on the volume.
//
// Single writer: the config and metadata live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='audiobookshelf',
  image='ghcr.io/advplyr/audiobookshelf:2.35.1',
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  // Audiobookshelf keeps config, metadata, and the library in separate trees;
  // surface metadata and the library as subpaths of the same volume as config.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/metadata', subPath: 'metadata' },
          { name: 'store', mountPath: '/audiobooks', subPath: 'audiobooks' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
