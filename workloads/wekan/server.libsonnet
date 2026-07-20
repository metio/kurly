// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wekan — a Wekan server (a self-hosted, open-source kanban board, à la Trello). A
// plain composable kurly.http workload on the official image, backed by an external
// MongoDB. Import it, point it at MongoDB, and render with kurly.list:
//
//   local wekan = import 'github.com/metio/kurly/workloads/wekan/server.libsonnet';
//   kurly.list(wekan(rootUrl='https://boards.example.com'))
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: Wekan reads MONGO_URL from the environment. kurly authors no
// Secret; provide one holding it, pulled in via envFrom. Pairs with a mongodb-cluster
// named wekan-db.
//
// Stateless: card attachments live in MongoDB (GridFS) by default, not on a volume, so
// this is a plain rolling Deployment that scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wekan',
  image='docker.io/wekan/wekan:v10.03',
  replicas=2,
  // The public URL (Wekan builds absolute links and validates it).
  rootUrl=null,
  // The Secret holding MONGO_URL (kurly mints none), via envFrom.
  secretName='wekan-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { PORT: '8080', WRITABLE_PATH: '/tmp' }
    + (if rootUrl == null then {} else { ROOT_URL: rootUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
