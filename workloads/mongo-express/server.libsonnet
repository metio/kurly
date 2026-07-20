// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mongo-express — a mongo-express server (a lightweight, web-based MongoDB admin UI: browse
// databases and collections, run queries and edit documents from the browser). A plain
// composable kurly.http workload on the official image. It holds no state — it connects to
// the MongoDB you point it at — so it is a plain stateless Deployment. Import it, point it
// at MongoDB, and render with kurly.list:
//
//   local mongoExpress = import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet';
//   kurly.list(mongoExpress())
//
// Serves the web app on :8081 — compose an exposure onto it.
//
// TARGET & SECRETS: mongo-express reads its MongoDB connection (ME_CONFIG_MONGODB_URL) and
// its basic-auth credentials from the environment. kurly authors no Secret; provide one
// holding them, pulled in via envFrom. Pairs with a mongodb-cluster.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mongo-express',
  image='docker.io/library/mongo-express:1.0.2',
  replicas=2,
  secretName='mongo-express-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8081)
  + kurly.servicePort(8081)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
