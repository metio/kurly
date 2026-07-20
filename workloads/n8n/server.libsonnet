// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// n8n — an n8n server (a fair-code workflow-automation tool: connect apps and
// automate tasks with a visual editor). A plain composable kurly.http workload: it
// keeps its workflows, credentials, and encryption key in a SQLite database on a
// PersistentVolume by default, so it needs no external database. Import it and render
// with kurly.list:
//
//   local n8n = import 'github.com/metio/kurly/workloads/n8n/server.libsonnet';
//   kurly.list(n8n(host='n8n.example.com'))
//
// Serves the editor, API, and webhooks on :5678 — compose an exposure onto it.
//
// Single writer: the SQLite database (and the auto-generated encryption key) live on
// a ReadWriteOnce volume, so one replica, recreated (never rolled) to keep two pods
// off the file. Point DB_TYPE at external PostgreSQL and set N8N_ENCRYPTION_KEY (from
// a Secret, via env) to scale out.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='n8n',
  image='docker.io/n8nio/n8n:2.31.4',
  storageSize='2Gi',
  storageClass=null,
  // The public hostname n8n serves at (webhook URLs need it).
  host=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    N8N_PORT: '5678',
    N8N_USER_FOLDER: '/home/node/.n8n',
  } + (if host == null then {} else { N8N_HOST: host, WEBHOOK_URL: 'https://' + host + '/' });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5678)
  + kurly.servicePort(5678)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/home/node/.n8n', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
