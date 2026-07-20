// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// penpot (frontend) — the Penpot frontend: the nginx-served web app that users load, which
// proxies API calls to the backend and export requests to the exporter. This is the user-facing
// stage of Penpot (the self-hosted, open-source Figma alternative). Import it and render with
// kurly.list:
//
//   local frontend = import 'github.com/metio/kurly/workloads/penpot/frontend.libsonnet';
//   kurly.list(frontend())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// It reaches the other stages by their in-cluster Service names through backendUri/exporterUri;
// keep these in step with the backend and exporter workload names. It is a static server with no
// state, so it scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='penpot-frontend',
  image='docker.io/penpotapp/frontend:2.3.2',
  replicas=2,
  backendUri='http://penpot-backend:6060',
  exporterUri='http://penpot-exporter:6061',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ PENPOT_BACKEND_URI: backendUri, PENPOT_EXPORTER_URI: exporterUri } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
