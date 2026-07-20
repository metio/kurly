// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// glance — a Glance server (a self-hosted dashboard that puts your feeds, RSS, weather,
// markets, monitoring and homelab widgets on one fast page). A plain composable kurly.http
// workload on the official image. Its whole layout is its glance.yml, mounted as a
// ConfigMap; it keeps no persistent state of its own. Import it, pass your config, and render
// with kurly.list:
//
//   local glance = import 'github.com/metio/kurly/workloads/glance/server.libsonnet';
//   kurly.list(glance(config={ pages: [ ... ] }))
//
// Serves the dashboard on :8080 — compose an exposure onto it.
//
// CONFIG IS THE WORKLOAD: `config` is Glance's own glance.yml schema (pages, columns,
// widgets), which kurly does not model — a second-hand copy would drift against Glance's — so
// it is rendered to the mounted glance.yml verbatim. The default shows a minimal page;
// replace it with your own.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');

local defaultConfig = {
  pages: [
    {
      name: 'Home',
      columns: [
        { size: 'full', widgets: [{ type: 'clock' }, { type: 'calendar' }] },
      ],
    },
  ],
};

function(
  name='glance',
  image='docker.io/glanceapp/glance:v0.8.4',
  config=defaultConfig,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.config({ 'glance.yml': std.manifestYamlDoc(config) }, mountPath='/app/config')
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
