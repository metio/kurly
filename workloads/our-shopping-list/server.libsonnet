// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// our-shopping-list — an Our Shopping List server (shared shopping and todo lists,
// synchronised live between everyone looking at a board). A plain composable
// kurly.http workload on the official image, backed by an external MongoDB. Import
// it, point it at MongoDB, and render with kurly.list:
//
//   local osl = import 'github.com/metio/kurly/workloads/our-shopping-list/server.libsonnet';
//   kurly.list(osl(dbHost='mongodb.example.svc'))
//
// Serves the web app and its socket.io endpoint on :8080 — compose an exposure onto
// it. The live update is a WebSocket, so an exposure that does not upgrade the
// connection leaves a UI that loads and never changes under anybody else's edits.
//
// DATABASE: the connection is HOST, PORT and DATABASE NAME, and nothing else —
// upstream states MongoDB authentication is not supported yet, so there is no
// credential to put in a Secret and kurly declares none. That is a property of the
// application, not an omission here: reach it over a network the database is not
// exposed on rather than with a password it will not read.
//
// Stateless: every board and item lives in MongoDB and the client bundle is baked
// into the image, so this is a plain rolling Deployment that scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='our-shopping-list',
  image=defaultImage,
  replicas=2,
  port=8080,
  // The MongoDB the boards are stored in. No credentials: the application does not
  // support authenticating against MongoDB.
  dbHost='mongodb',
  dbPort=27017,
  dbName='osl',
  // The path the app is served under when it is not the web root, e.g. '/osl/'.
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      LISTEN_PORT: std.toString(port),
      MONGODB_HOST: dbHost,
      MONGODB_PORT: std.toString(dbPort),
      MONGODB_DB: dbName,
    }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env(baseEnv + env)
  // The image selects no account; the application only reads its own install tree.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  // The health endpoint answers plainly on the web root the app is served under.
  + kurly.readinessProbe({ httpGet: { path: (if baseUrl == null then '' else std.rstripChars(baseUrl, '/')) + '/healthcheck', port: 'http' } })
  // Liveness by connection: the health endpoint reports the database too, and a
  // MongoDB outage should leave the pod unready rather than restarting it forever.
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
