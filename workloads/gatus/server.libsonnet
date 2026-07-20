// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gatus — a Gatus server (a self-hosted, developer-oriented health dashboard and status
// page: it probes your endpoints on a schedule, evaluates conditions and alerts). A plain
// composable kurly.http workload on the official image. Its whole behaviour is its
// configuration — the endpoints to watch and the conditions that make them healthy — which
// is mounted as a ConfigMap; its history database lives on a PersistentVolume. Import it,
// pass your config, and render with kurly.list:
//
//   local gatus = import 'github.com/metio/kurly/workloads/gatus/server.libsonnet';
//   kurly.list(gatus(config={ endpoints: [ ... ] }))
//
// Serves the status page and API on :8080 — compose an exposure onto it.
//
// CONFIG IS THE WORKLOAD: `config` is Gatus's own schema (endpoints, conditions, alerting,
// storage, ui), which kurly does not model — a second-hand copy would drift against Gatus's
// and lie about what it accepts — so it is rendered to the mounted config.yaml verbatim. The
// default watches one sample endpoint and persists history to SQLite; replace it with your
// own. The default keeps SQLite under the data volume so history survives restarts.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// A working default: persist to SQLite on the data volume and watch one endpoint. A real
// deployment replaces `endpoints` (and usually adds `alerting`).
local defaultConfig = {
  storage: { type: 'sqlite', path: '/data/gatus.db' },
  endpoints: [
    {
      name: 'website',
      group: 'core',
      url: 'https://example.org',
      interval: '5m',
      conditions: ['[STATUS] == 200'],
    },
  ],
};

function(
  name='gatus',
  image='docker.io/twinproduction/gatus:v5.36.0',
  storageSize='1Gi',
  storageClass=null,
  config=defaultConfig,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // Gatus reads /config/config.yaml; JSON is valid YAML, but manifestYamlDoc keeps the
  // rendered ConfigMap readable when someone kubectl-gets it.
  + kurly.config({ 'config.yaml': std.manifestYamlDoc(config) }, mountPath='/config')
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
