// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hister — a Hister server (a personal web search engine that indexes the sites you
// visit, keeps offline previews of them and can search them semantically). A plain
// composable kurly.http workload on the official image; its index, previews and its
// config.yml live together on a PersistentVolume, so it needs no external database.
// Import it, adapt with the parameters below, and render with kurly.list:
//
//   local hister = import 'github.com/metio/kurly/workloads/hister/server.libsonnet';
//   kurly.list(hister(baseUrl='https://search.example.com'))
//
// Serves the web app on :4433 — compose an exposure onto it.
//
// LISTEN ADDRESS: Hister binds a loopback address by default, which no probe and no
// Service can reach, so the stage sets HISTER__SERVER__ADDRESS to 0.0.0.0 on the
// declared port. It also reads HISTER_PORT — the very name Kubernetes injects for a
// Service called hister, as a tcp:// URL — so service links are disabled; with them
// on, the address becomes 0.0.0.0:tcp://<clusterIP>:4433 and the server refuses to
// listen.
//
// CONFIGURATION: the image points HISTER_CONFIG at /hister/data/config.yml, on the
// same volume as the data, so every setting is either an HISTER__<SECTION>__<KEY>
// environment variable (via env) or an edit to that file. PostgreSQL, semantic
// search and OAuth are configured that way; none is needed to run.
//
// Single writer: the index lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='hister',
  image=defaultImage,
  port=4433,
  storageSize='10Gi',
  storageClass=null,
  // The public URL (Hister builds links from it behind a reverse proxy).
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { HISTER__SERVER__BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env({
    HISTER__SERVER__ADDRESS: '0.0.0.0:%d' % port,
    HISTER_DATA_DIR: '/hister/data',
    HISTER_CONFIG: '/hister/data/config.yml',
  } + baseEnv + env)
  + kurly.disableServiceLinks()
  + kurly.runAs(65532, gid=65532, fsGroup=65532)
  + kurly.store('/hister/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
