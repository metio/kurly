// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// agentgateway — a proxy that puts several MCP servers, A2A servers and HTTP APIs
// behind one endpoint, applying policies (CORS, authentication, rate limiting) on
// the way through. A plain composable kurly.http workload: the whole gateway is
// its configuration file, rendered here as a ConfigMap, so it keeps nothing.
// Import it and render with kurly.list:
//
//   local agentgateway = import 'github.com/metio/kurly/workloads/agentgateway/gateway.libsonnet';
//   kurly.list(agentgateway(targets=[{
//     name: 'weather',
//     mcp: { host: 'weather-mcp', port: 8080, path: '/mcp' },
//   }]))
//
// Serves proxied MCP traffic on :3000 — compose an exposure onto it.
//
// STDIO TARGETS RUN A COMMAND IN THIS CONTAINER. A target declared with `stdio`
// makes the gateway fork a process (`npx …`, a local binary) and speak MCP over
// its pipes, which means the target can do whatever this pod can do and needs a
// binary this image ships — it ships none of them. In a cluster the arrangement
// that works is an HTTP target pointing at an MCP server running as its own
// workload, which is what the default composes.
//
// Stateless: nothing is written outside /tmp, which is a scratch volume, so the
// root filesystem stays read-only and replicas scale freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './gateway.image', '\n');

function(
  name='agentgateway',
  image=defaultImage,
  replicas=2,
  port=3000,
  // The MCP servers exposed through the gateway, verbatim — the `mcp.targets`
  // list of its configuration.
  targets=[],
  // Merged over the rendered configuration — policies, listeners, telemetry.
  config={},
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.args(['-f', '/etc/agentgateway/config.yaml'])
  + kurly.env(env)
  // The uid the image already runs as.
  + kurly.runAs(65532, gid=65532)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.config({
    'config.yaml': std.manifestYamlDoc({
      mcp: { port: port, targets: targets },
    } + config, quote_keys=false),
  }, mountPath='/etc/agentgateway')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
