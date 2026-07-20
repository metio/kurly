// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// karakeep — a Karakeep server (a self-hosted "bookmark everything" app, formerly
// Hoarder: save links, notes and images and search them with AI tagging). A plain
// composable kurly.http workload on the official image; its SQLite database and stored
// assets live on a PersistentVolume. Import it, point it at its companions, and render
// with kurly.list:
//
//   local karakeep = import 'github.com/metio/kurly/workloads/karakeep/server.libsonnet';
//   kurly.list(karakeep(nextauthUrl='https://bookmarks.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// COMPANIONS: Karakeep expects two side services it does not bundle here — a Meilisearch
// instance for full-text search (MEILI_ADDR + MEILI_MASTER_KEY) and a headless Chrome
// for fetching page content (BROWSER_WEB_URL). Run them alongside and point the env at
// them; the web app starts without them but search and crawling stay degraded until
// they are reachable.
//
// SECRETS: Karakeep reads NEXTAUTH_SECRET, MEILI_MASTER_KEY and any AI provider key
// (OPENAI_API_KEY, …) from the environment. kurly authors no Secret; provide one holding
// them, pulled in via envFrom.
//
// Single writer: the SQLite database and assets live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='karakeep',
  image='ghcr.io/karakeep-app/karakeep:v0.32.0',
  storageSize='10Gi',
  storageClass=null,
  // The public URL (NextAuth needs it).
  nextauthUrl=null,
  // The Meilisearch endpoint and the headless-Chrome debugging endpoint.
  meiliAddr='http://meilisearch:7700',
  browserWebUrl='http://chrome:9222',
  // The Secret holding NEXTAUTH_SECRET, MEILI_MASTER_KEY and any AI provider key
  // (kurly mints none), via envFrom.
  secretName='karakeep-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { DATA_DIR: '/data', MEILI_ADDR: meiliAddr, BROWSER_WEB_URL: browserWebUrl }
    + (if nextauthUrl == null then {} else { NEXTAUTH_URL: nextauthUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
