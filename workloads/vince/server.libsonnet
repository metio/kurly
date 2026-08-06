// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vince — a Vince server (privacy-friendly web analytics: a script on a site
// posts events here and a dashboard reports them, without cookies and without
// following anybody between sites). A plain composable kurly.http workload: one
// static Go binary keeping its embedded Pebble database on a PersistentVolume,
// with no database, cache or object storage beside it. Import it and render with
// kurly.list:
//
//   local vince = import 'github.com/metio/kurly/workloads/vince/server.libsonnet';
//   kurly.list(vince())
//
// Serves the dashboard, the event API and the tracking script on :8080 — compose
// an exposure onto it.
//
// `url` is the address browsers reach this instance at, and the tracking snippet
// the dashboard hands out is built from it, so a wrong value produces a snippet
// that posts events nowhere. It has no sane default for a real deployment, which
// is why it is a parameter rather than a value baked in here.
//
// Automatic TLS is deliberately left off: a certificate belongs to the exposure
// composed in front of this, and the ACME client here would want :443 published
// straight at the pod.
//
// Single writer: one embedded key-value store on a ReadWriteOnce volume, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='vince',
  image=defaultImage,
  // The Pebble database holding every event ever recorded — it grows with traffic,
  // not with the number of sites.
  storageSize='10Gi',
  storageClass=null,
  // The address browsers reach this instance at. The tracking snippet is built
  // from it, so set it to the host the exposure serves.
  url='http://localhost:8080',
  // Sites created on startup, so a fresh instance is usable without clicking
  // through the dashboard first.
  domains=[],
  // The Secret holding VINCE_ADMIN_NAME and VINCE_ADMIN_PASSWORD. Vince creates
  // that account on startup when both are set; without it nobody can log in, since
  // there is no sign-up in a self-hosted Vince.
  secretName='vince',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image's entrypoint is the bare binary, which prints help and exits without
  // a subcommand.
  + kurly.args(['serve'])
  + kurly.env(
    {
      VINCE_LISTEN: ':8080',
      VINCE_DATA: '/data',
      VINCE_URL: url,
    } + (if domains == [] then {} else { VINCE_DOMAINS: std.join(',', domains) }) + env
  )
  + kurly.envFromSecret(secretName)
  // A single static binary that selects no account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Opening the database and building the first indexes happens before the listener
  // does, and on a volume that already holds events it is not instant.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
