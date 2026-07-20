// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docker-registry-ui — a Docker Registry UI server (a clean, self-hosted web interface for
// browsing a Docker/OCI registry: list repositories and tags, inspect and delete images). A
// plain composable kurly.http workload on the official image. It holds no state — it talks to
// the registry you point it at — so it is a plain stateless Deployment. Import it, point it at
// a registry, and render with kurly.list:
//
//   local ui = import 'github.com/metio/kurly/workloads/docker-registry-ui/server.libsonnet';
//   kurly.list(ui(registryUrl='https://registry.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// TARGET: point it at your registry through REGISTRY_URL (registryUrl below). Deleting images
// needs the registry to allow it and REGISTRY_ALLOW_DELETE=true.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='docker-registry-ui',
  image='docker.io/joxit/docker-registry-ui:2.5.7',
  replicas=2,
  registryUrl=null,
  registryTitle='Docker Registry',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { NGINX_PROXY_PASS_URL: 'unset', SINGLE_REGISTRY: 'true', REGISTRY_TITLE: registryTitle }
    + (if registryUrl == null then {} else { NGINX_PROXY_PASS_URL: registryUrl });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
  // The bundled nginx serves on :80 as the root master, then workers drop privileges; the
  // root filesystem stays writable for nginx's runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
