// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ezbookkeeping — an ezBookkeeping server (a lightweight personal finance and
// accounting app: accounts, transactions, categories and reports, with a
// mobile-friendly UI). A plain composable kurly.http workload: with the default
// SQLite backend its database and uploaded attachments live on a PersistentVolume,
// so it needs nothing external. Import it and render with kurly.list:
//
//   local ezbookkeeping = import 'github.com/metio/kurly/workloads/ezbookkeeping/server.libsonnet';
//   kurly.list(ezbookkeeping())
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file. Point the EBK_DATABASE_*
// settings at MySQL or PostgreSQL through env to move the database off the volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ezbookkeeping',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding EBK_SECURITY_SECRET_KEY, which signs the tokens users hold.
  // Supplied rather than left to the shipped default: the image ships a PUBLISHED
  // one, so an instance running with it accepts tokens anybody can mint.
  secretName='ezbookkeeping',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // The image already selects its own account, so nothing is relaxed; fsGroup is
  // what makes the volume writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/ezbookkeeping/data', storageSize, storageClass=storageClass)
  // The server writes its log and any uploaded attachments beside its own binary,
  // neither of which is worth a volume.
  + kurly.scratch('/ezbookkeeping/log')
  + kurly.scratch('/ezbookkeeping/storage')
  // It publishes no health endpoint — /healthz and the usual variants all answer
  // 404 — so the probes ask for the app itself, which returns 200 without
  // authentication.
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
