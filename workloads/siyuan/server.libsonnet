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
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='siyuan',
  image=defaultImage,
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
  // The kernel takes a subcommand; without one it prints its usage and exits.
  + kurly.args(['serve', '--workspace=/siyuan/workspace'])
  + kurly.env(env)
  // The entrypoint creates its account and hands the workspace to it.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
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
