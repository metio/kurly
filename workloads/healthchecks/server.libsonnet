// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// healthchecks — a Healthchecks server (a self-hosted cron-job and background-task
// monitoring service: your jobs ping a URL when they finish, and it alerts you when a ping
// is late or missing — "dead man's switch" monitoring). A plain composable kurly.http
// workload on the official image; with the default SQLite backend its database lives on a
// PersistentVolume. Import it, adapt with the parameters below, and render with kurly.list:
//
//   local healthchecks = import 'github.com/metio/kurly/workloads/healthchecks/server.libsonnet';
//   kurly.list(healthchecks(siteRoot='https://checks.example.com', allowedHosts='checks.example.com'))
//
// Serves the web app and ping API on :8000 — compose an exposure onto it.
//
// SECRET & DATABASE: Healthchecks needs SECRET_KEY. kurly authors no Secret; provide one
// holding it, pulled in via envFrom. Point it at an external PostgreSQL (DB=postgres plus
// the DB_* connection) to scale past the single SQLite writer.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='healthchecks',
  image='docker.io/healthchecks/healthchecks:v4.3',
  storageSize='2Gi',
  storageClass=null,
  // The public URL, and the hosts the app answers on.
  siteRoot=null,
  allowedHosts=null,
  // The Secret holding SECRET_KEY (kurly mints none), via envFrom.
  secretName='healthchecks-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { DB: 'sqlite', DB_NAME: '/data/hc.sqlite' }
    + (if siteRoot == null then {} else { SITE_ROOT: siteRoot })
    + (if allowedHosts == null then {} else { ALLOWED_HOSTS: allowedHosts });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
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
