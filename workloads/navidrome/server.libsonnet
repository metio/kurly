// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// navidrome — a Navidrome server (a modern music server and streamer, compatible
// with Subsonic/Airsonic clients). A plain composable kurly.http workload on the
// official image: it keeps its database on a PersistentVolume and reads your music
// library from it, so it needs no external database. Import it and render with
// kurly.list:
//
//   local navidrome = import 'github.com/metio/kurly/workloads/navidrome/server.libsonnet';
//   kurly.list(navidrome())
//
// Serves the web UI and Subsonic API on :4533 — compose an exposure onto it. Put
// your music under /music on the volume.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='navidrome',
  image='docker.io/deluan/navidrome:0.63.2',
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local library = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/music', subPath: 'music', readOnly: true }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4533)
  + kurly.servicePort(4533)
  + kurly.env({ ND_MUSICFOLDER: '/music', ND_DATAFOLDER: '/data', ND_PORT: '4533' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + library
