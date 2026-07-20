// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// misskey — a Misskey server (a self-hosted, feature-rich ActivityPub/Fediverse social platform
// with a highly customizable UI). A plain composable kurly.http workload on the official image,
// backed by an external PostgreSQL and Redis, with uploaded files on a PersistentVolume. Import
// it, point it at a config, and render with kurly.list:
//
//   local misskey = import 'github.com/metio/kurly/workloads/misskey/server.libsonnet';
//   kurly.list(misskey())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// CONFIG & SECRETS: Misskey reads its whole configuration — including the PostgreSQL and Redis
// credentials and the instance URL — from /misskey/.config/default.yml. Because that file holds
// secrets, kurly mounts it from an EXISTING Secret you provide (kurly never mints key material):
// create a Secret with a default.yml key and it is mounted read-only. Pairs with a cnpg-cluster
// and a Redis.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica, recreated (point
// object storage at S3 in default.yml to scale out).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='misskey',
  image='docker.io/misskey/misskey:2024.11.0',
  storageSize='20Gi',
  storageClass=null,
  configSecret='misskey-config',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  // The config file carries DB/Redis credentials, so it comes from a Secret, not a ConfigMap.
  + kurly.secretMount(configSecret, '/misskey/.config')
  + kurly.store('/misskey/files', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
