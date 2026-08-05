// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// isso — an Isso server (a small comment server for static sites: a script tag on
// the page, comments in SQLite, no accounts and no third party). A plain
// composable kurly.http workload. Import it and render with kurly.list:
//
//   local isso = import 'github.com/metio/kurly/workloads/isso/server.libsonnet';
//   kurly.list(isso(host='https://example.com'))
//
// Serves the comment API and the embedded widget on :8080 — compose an exposure
// onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// A starter configuration, replaced wholesale by passing `config`. `host` is the
// part that cannot be defaulted: Isso serves comments only for pages under the
// origins listed there and answers requests from anywhere else with an error, so
// the value has to be the site the comments belong to.
local defaultConfig(host) = |||
  [general]
  dbpath = /db/comments.db
  host = %s
  max-age = 15m

  [server]
  listen = http://0.0.0.0:8080/

  [guard]
  enabled = true
  ratelimit = 2
  direct-reply = 3
  reply-to-self = false
  require-author = true

  [markup]
  options = strikethrough, superscript, autolink
||| % host;

function(
  name='isso',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The site whose pages may embed these comments. REQUIRED: Isso rejects requests
  // from any other origin, so a wrong value produces a widget that loads and then
  // refuses every comment.
  host=null,
  config=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      // gunicorn puts its control-server socket in $HOME/.gunicorn, and the uid
      // named below has no home directory — so HOME resolves to / and the socket
      // lands on the read-only root filesystem. The server still serves, which is
      // why this is worth setting rather than ignoring: the only symptom is one
      // ERROR line at startup, repeated forever in the logs of a workload that is
      // otherwise working.
      HOME: '/tmp',
    } + env
  )
  + kurly.config(
    { 'isso.cfg': if config != null then config else defaultConfig(if host == null then 'http://localhost' else host) },
    mountPath='/config',
    subPath=true
  )
  // gunicorn and Isso need nothing root provides; the image simply never selects
  // an account.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/db', storageSize, storageClass=storageClass)
  // The image's own entrypoint passes --worker-tmp-dir /dev/shm, so gunicorn's
  // heartbeat files land there rather than on disk. The 64MiB default is ample for
  // four workers, but it must be writable.
  + kurly.scratch('/dev/shm', '64Mi')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/?uri=/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/?uri=/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
