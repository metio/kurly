// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// siyuan — a SiYuan server (a privacy-first, self-hosted personal knowledge-management
// and note-taking app with block-level editing and a local-first workspace). A plain
// composable kurly.http workload on the official image; its workspace (notes, assets and
// the database) lives on a PersistentVolume. Import it, adapt with the parameters below,
// and render with kurly.list:
//
//   local siyuan = import 'github.com/metio/kurly/workloads/siyuan/server.libsonnet';
//   kurly.list(siyuan())
//
// Serves the web app on :6806 — compose an exposure onto it.
//
// ACCESS CODE: SiYuan's web access is gated by an access-auth code. Set it through the
// SIYUAN_ACCESS_AUTH_CODE environment variable (from a Secret via kurly.envFromSecret);
// kurly authors no Secret.
//
// Single writer: the workspace lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='siyuan',
  image='docker.io/b3log/siyuan:v3.7.2',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6806)
  + kurly.servicePort(6806)
  + kurly.args(['--workspace=/siyuan/workspace'])
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/siyuan/workspace', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
