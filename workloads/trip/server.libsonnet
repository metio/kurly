// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// trip — a TRIP server (a minimalist map tracker and trip planner: pin the places
// you care about on a map and plan multi-day itineraries around them). A plain
// composable kurly.http workload keeping its SQLite database, its configuration
// file, uploaded images and attachments under /app/storage on a PersistentVolume,
// so it needs no external database. Import it and render with kurly.list:
//
//   local trip = import 'github.com/metio/kurly/workloads/trip/server.libsonnet';
//   kurly.list(trip())
//
// Serves the single-page frontend and the API on :8000 — compose an exposure onto
// it. /api/info answers unauthenticated, which is what the probes read.
//
// SECRET_KEY signs the tokens users hold. The app mints one into
// storage/config.env on first start when the environment carries none, so a Secret
// is optional; pass one through secretName to keep sessions alive across a rebuilt
// volume. kurly authors no Secret. Every other setting is a pydantic field too, so
// anything from the configuration file — OIDC_*, REGISTER_ENABLE, DEFAULT_TILE —
// can be handed in through env instead, where an environment variable wins over
// the file.
//
// The map tiles are fetched by the BROWSER, not by the pod, so a NetworkPolicy that
// blocks egress does not blank the map. OIDC login is the exception: the discovery
// URL is fetched server-side and needs egress to the provider.
//
// The image selects no user and needs nothing root provides, so it runs as 1000
// under the hardened default; the volume is group-owned through fsGroup.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='trip',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // An optional Secret holding SECRET_KEY and any OIDC credentials, via envFrom.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + (if secretName == null then {} else kurly.envFromSecret(secretName))
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Everything the app writes — the SQLite database, config.env, assets,
  // attachments and backups — is relative to the /app working directory, under
  // storage/. The volume is mounted there and the root filesystem stays read-only.
  + kurly.store('/app/storage', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
