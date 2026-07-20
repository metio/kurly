// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailhog — a MailHog server (a self-hosted email-testing tool for developers: it captures the
// mail your apps send and shows it in a web inbox instead of delivering it). A plain composable
// kurly.http workload on the official image. It keeps captured mail in memory, so it is a plain
// stateless Deployment. Import it and render with kurly.list:
//
//   local mailhog = import 'github.com/metio/kurly/workloads/mailhog/server.libsonnet';
//   kurly.list(mailhog())
//
// Serves the web inbox on :8025 — compose an exposure onto it. Apps send mail to its SMTP
// listener on :1025, published on the Service beside the web port (the 'smtp' port).
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mailhog',
  image='docker.io/mailhog/mailhog:latest@sha256:8d76a3d4ffa32a3661311944007a415332c4bb855657f4f6c57996405c009bea',
  replicas=1,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8025)
  + kurly.servicePort(8025)
  + kurly.extraPort('smtp', 1025)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
