// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// outline — an Outline server (a fast, collaborative, self-hosted team knowledge base and wiki
// with real-time editing). A plain composable kurly.http workload on the official image, backed
// by an external PostgreSQL, Redis and S3-compatible object storage (for uploads). Import it,
// point it at its backends, and render with kurly.list:
//
//   local outline = import 'github.com/metio/kurly/workloads/outline/server.libsonnet';
//   kurly.list(outline(url='https://wiki.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Outline reads DATABASE_URL, REDIS_URL, SECRET_KEY, UTILS_SECRET, the S3
// settings (AWS_* / S3 endpoint) and at least one authentication provider (OIDC, Google, Slack…)
// from the environment. kurly authors no Secret; provide one holding them, via envFrom. The
// defaults pair with a cnpg-cluster named outline-db, a Redis and an S3 bucket (e.g. seaweedfs).
//
// Stateless: documents live in PostgreSQL and uploads in S3, so this is a plain rolling
// Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='outline',
  image='docker.io/outlinewiki/outline:0.81.1',
  replicas=2,
  url=null,
  secretName='outline-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if url == null then {} else { URL: url };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
