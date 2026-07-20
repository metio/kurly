// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// element-web — an Element Web server (the popular self-hosted web client for the Matrix
// network: chat, calls and end-to-end-encrypted rooms in the browser). A plain composable
// kurly.http workload on the official image. It serves a static app configured by a single
// config.json, which is mounted — via a subPath ConfigMap mount — into the web root beside the
// app's own files, so it keeps no state and is a plain stateless Deployment. Import it, point
// it at a homeserver, and render with kurly.list:
//
//   local element = import 'github.com/metio/kurly/workloads/element-web/server.libsonnet';
//   kurly.list(element(homeserverUrl='https://matrix.example.com', serverName='example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// HOMESERVER: Element is only a client; point it at a Matrix homeserver (e.g. the
// matrix-conduit workload) through homeserverUrl/serverName, which populate config.json's
// default_server_config. Pass `config` to override or extend the rest of Element's config.json
// verbatim (kurly does not model its schema).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='element-web',
  image='ghcr.io/element-hq/element-web:v1.11.100',
  replicas=2,
  homeserverUrl=null,
  serverName=null,
  brand='Element',
  config={},
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local configJson = {
    brand: brand,
    default_server_config: { 'm.homeserver': std.prune({ base_url: homeserverUrl, server_name: serverName }) },
    disable_guests: true,
  } + config;
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  // A single file mounted into the web root beside the app's assets, not over them.
  + kurly.config({ 'config.json': std.manifestJsonEx(configJson, '  ') }, mountPath='/app', subPath=true)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
