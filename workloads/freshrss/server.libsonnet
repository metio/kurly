// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// freshrss — a FreshRSS server (a free, self-hosted RSS and Atom feed aggregator).
// A plain composable kurly.http workload on the official image: it keeps its feeds
// and articles in a SQLite database on a PersistentVolume by default, so it needs no
// external database. Import it and render with kurly.list:
//
//   local freshrss = import 'github.com/metio/kurly/workloads/freshrss/server.libsonnet';
//   kurly.list(freshrss())
//
// Serves the web app and API on :80 — compose an exposure onto it. Point it at an
// external PostgreSQL/MySQL through the setup wizard (or env) to scale past the
// single SQLite writer.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='freshrss',
  image='docker.io/freshrss/freshrss:1.29.1',
  storageSize='2Gi',
  storageClass=null,
  // The public base URL FreshRSS trusts and builds links against.
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    TZ: 'UTC',
    CRON_MIN: '*/20',
  } + (if baseUrl == null then {} else { FRESHRSS_ENV: 'production', BASE_URL: baseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/FreshRSS/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/i/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
