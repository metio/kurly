// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// restreamer — a datarhei Restreamer server (a complete streaming server with a
// web UI: take a camera or an RTMP feed in, transcode it with FFmpeg, and publish
// it as HLS to a website or on to YouTube, Twitch and the rest). A plain
// composable kurly.http workload: its configuration and recordings live on
// PersistentVolumes. Import it and render with kurly.list:
//
//   local restreamer = import 'github.com/metio/kurly/workloads/restreamer/server.libsonnet';
//   kurly.list(restreamer())
//
// Serves the web UI and HLS on :8080 — compose an exposure onto it. The ingest
// protocols are separate Service ports and none of them is HTTP:
//
//   1935/TCP   RTMP
//   1936/TCP   RTMPS
//   6000/UDP   SRT
//
// Route those with a TCPRoute/UDPRoute or a LoadBalancer if publishers are outside
// the cluster.
//
// TRANSCODING IS CPU WORK, and the defaults here reflect that: FFmpeg will use
// everything it is given. The limit is what stops one busy stream starving its
// neighbours, so raise it deliberately rather than removing it.
//
// Single writer: one configuration and recording volume pair, ReadWriteOnce, so
// one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='restreamer',
  image=defaultImage,
  configSize='1Gi',
  dataSize='20Gi',
  storageClass=null,
  // The Secret holding CORE_API_AUTH_USERNAME and CORE_API_AUTH_PASSWORD. Without
  // them the first visitor to the web UI is invited to create the administrator,
  // which on an exposed instance is whoever finds it first.
  secretName='restreamer',
  env={},
  resources={ requests: { cpu: '500m', memory: '512Mi' }, limits: { cpu: '2', memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('rtmp', 1935)
  + kurly.extraPort('rtmps', 1936)
  + kurly.extraPort('srt', 6000, protocol='UDP')
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // Nothing here needs root: every port is above 1024 and everything written is on
  // a volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/core/config', configSize, storageClass=storageClass)
  + kurly.store('/core/data', dataSize, storageClass=storageClass)
  // FFmpeg stages segments and muxes through temporary files.
  + kurly.scratch('/tmp')
  // /ping answers 200 without authentication; the UI itself does not.
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
