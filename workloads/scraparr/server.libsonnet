// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// scraparr — a Prometheus exporter for the *arr media stack (Sonarr, Radarr,
// Prowlarr, Bazarr, Jellyseerr, Jellyfin, Komga and the rest). A plain composable
// kurly.http workload: it polls each service's API and serves the result as
// metrics, keeping nothing, so it claims no volume and needs no database. Import
// it and render with kurly.list:
//
//   local scraparr = import 'github.com/metio/kurly/workloads/scraparr/server.libsonnet';
//   kurly.list(scraparr(services={ sonarr: { url: 'http://sonarr:8989', api_key: '${SONARR_API_KEY}' } }, secretName='scraparr'))
//
// Serves /metrics on :7100 — compose a kurly.serviceMonitor onto it (or an
// exposure, if something outside the cluster scrapes it).
//
// API KEYS DO NOT BELONG IN THE CONFIGMAP. scraparr substitutes ${VAR} in its
// config.yaml from the environment, so a service's api_key is written as
// '${SONARR_API_KEY}' here and the value comes from the Secret `secretName`
// names. Writing the key inline would put it in a ConfigMap, readable by anything
// that can read ConfigMaps in the namespace.
//
// Stateless: any replica count is legal, but each replica polls every configured
// service on its own, so more than one multiplies the load on them for no gain.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='scraparr',
  image=defaultImage,
  // One entry per scraped service, keyed by connector name — see the project's
  // documentation for the fields each takes.
  services={},
  // How often each service is polled, in seconds.
  interval=30,
  // A Secret holding the API keys the config refers to as ${VAR}.
  secretName=null,
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(7100)
  + kurly.servicePort(7100)
  + kurly.config({
    'config.yaml': std.manifestYamlDoc({
      general: { port: 7100, interval: interval },
    } + services, quote_keys=false),
  }, mountPath='/scraparr/config')
  // The image runs as root by default; the exporter reads its configuration and
  // writes nothing, so an unprivileged uid serves.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '32Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/metrics', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/metrics', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
