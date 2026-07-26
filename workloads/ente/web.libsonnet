// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ente web — the browser front end for Ente: a single image bundling every web
// app (Photos on :3000, Albums :3002, Cast :3004, Share :3005, Embed :3006). It
// is a stateless static/Next.js server that talks to the museum API from the
// USER'S BROWSER, so apiOrigin must be the museum's PUBLIC URL (the one the
// browser can reach), not the in-cluster Service. Compose it beside the museum
// server stage:
//
//   local web = import 'github.com/metio/kurly/workloads/ente/web.libsonnet';
//   kurly.list(web(apiOrigin='https://ente-api.example.com'))
//
// Expose the Photos app (:3000) for the main UI; route the extra ports for the
// public-album, cast, and share apps if you use them. Stateless — no PVC — so
// scale it by replicas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='ente-web',
  // The web bundle publishes only commit-tagged and moving tags, so it is pinned
  // as latest@digest — a known artifact that Renovate refreshes.
  image='ghcr.io/ente/web:latest@sha256:d9fe114825b27bd51be61a091e61b0e64117edb5bfd8cfb419ea404d4170e614',
  // The museum API and the albums app, as the BROWSER reaches them (public URLs).
  apiOrigin='https://ente-api.example.com',
  albumsOrigin='https://albums.example.com',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  // The sibling web apps, each on its own port so an exposure can route them.
  + kurly.extraPort('albums', 3002)
  + kurly.extraPort('cast', 3004)
  + kurly.extraPort('share', 3005)
  + kurly.extraPort('embed', 3006)
  // A Next.js server writes its cache and temp files across the filesystem, so
  // pin a non-root uid and keep the root filesystem writable.
  + kurly.runAs(1000, gid=1000)
  + kurly.writableRootFilesystem()
  + kurly.env({ ENTE_API_ORIGIN: apiOrigin, ENTE_ALBUMS_ORIGIN: albumsOrigin } + env)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
