// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// planka — a Planka server (a self-hosted, real-time kanban board for teams, an open
// alternative to Trello). A plain composable kurly.http workload on the official image, backed
// by an external PostgreSQL. Planka stores uploads (avatars, backgrounds, attachments) either
// on local disk across three directories or in S3-compatible object storage; kurly wires it for
// S3 so it stays a plain stateless Deployment — pair it with the seaweedfs workload or any S3
// bucket. Import it, point it at its backends, and render with kurly.list:
//
//   local planka = import 'github.com/metio/kurly/workloads/planka/server.libsonnet';
//   kurly.list(planka(baseUrl='https://boards.example.com'))
//
// Serves the web app on :1337 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Planka reads DATABASE_URL, SECRET_KEY and its S3 settings (S3_ENDPOINT,
// S3_REGION, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY) from the environment, plus the
// initial admin credentials. kurly authors no Secret; provide one holding them, via envFrom.
// The defaults pair with a cnpg-cluster named planka-db and an S3 bucket (e.g. seaweedfs).
//
// Stateless with S3 uploads: a plain rolling Deployment. To use local-disk uploads instead,
// compose ReadWriteMany volumes onto the three upload paths and drop the S3 settings.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='planka',
  image='ghcr.io/plankanban/planka:2.1.1',
  replicas=2,
  baseUrl=null,
  secretName='planka-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { BASE_URL: baseUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(1337)
  + kurly.servicePort(1337)
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
