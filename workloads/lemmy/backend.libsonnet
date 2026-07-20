// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lemmy (backend) — the Lemmy backend: the API and federation server of Lemmy, the self-hosted,
// open-source link aggregator and forum for the Fediverse (a Reddit alternative). Lemmy runs as
// THREE workloads — this backend, a `ui` frontend, and a `pictrs` image server — backed by an
// external PostgreSQL. Import it, point it at a config, and render with kurly.list:
//
//   local backend = import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet';
//   kurly.list(backend())
//
// Serves the API on :8536 — the ui reaches it at http://lemmy:8536.
//
// CONFIG & SECRETS: Lemmy reads its configuration — including the PostgreSQL connection and the
// pict-rs API key — from /config/config.hjson. Because that holds secrets, kurly mounts it from
// an EXISTING Secret you provide (with a config.hjson key); kurly never mints key material.
// Pairs with a cnpg-cluster named lemmy-db.
//
// Stateless: content lives in PostgreSQL (and images in pict-rs), so this is a plain rolling
// Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='lemmy',
  image='docker.io/dessalines/lemmy:0.19.7',
  replicas=1,
  configSecret='lemmy-config',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8536)
  + kurly.servicePort(8536)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.secretMount(configSecret, '/config')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
