// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// apisix — a high-performance API gateway: routing, authentication, rate limiting
// and observability in front of upstream services. A plain composable kurly.http
// workload in APISIX's STANDALONE mode, where routes come from a YAML file rather
// than from etcd. Import it and render with kurly.list:
//
//   local apisix = import 'github.com/metio/kurly/workloads/apisix/gateway.libsonnet';
//   kurly.list(apisix(routes=[{
//     uri: '/orders/*',
//     upstream: { type: 'roundrobin', nodes: { 'orders:8080': 1 } },
//   }]))
//
// Serves proxied traffic on :9080 — compose an exposure onto it.
//
// STANDALONE, SO NO etcd. APISIX's default deployment keeps its configuration in
// an etcd cluster and reloads on change, which is a second stateful system to run
// and back up. This stage takes the other supported shape: the data plane reads
// apisix.yaml, rendered here as a ConfigMap, and that file is the whole
// configuration. The trade is that the admin API is not available — routes are
// changed by rendering again, which suits a gateway declared alongside the
// workloads it fronts.
//
// THE FILE MUST END WITH `#END`. APISIX treats that marker as the end of the
// configuration and IGNORES A FILE WITHOUT IT — no routes, no error worth the
// name, just a gateway answering 404 for everything. It is appended here rather
// than left to a caller.
//
// Stateless: nothing is written but logs, which go to a scratch volume, so the
// root filesystem stays read-only and replicas scale freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './gateway.image', '\n');

function(
  name='apisix',
  image=defaultImage,
  replicas=2,
  // APISIX route definitions, verbatim — the `routes` list of apisix.yaml.
  routes=[],
  // Anything else apisix.yaml carries: upstreams, services, plugin_configs,
  // consumers, global_rules.
  objects={},
  // Merged over the rendered config.yaml — APISIX's own runtime settings.
  config={},
  env={},
  resources={ requests: { cpu: '200m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9080)
  + kurly.servicePort(9080)
  + kurly.env(env)
  // The uid the image's own apisix user carries.
  + kurly.runAs(1000, gid=1000)
  // Access and error logs, the nginx client-body buffers, and the generated
  // nginx.conf APISIX writes at startup.
  + kurly.scratch('/usr/local/apisix/logs', '512Mi')
  + kurly.scratch('/usr/local/apisix/conf/cert', '8Mi')
  + kurly.scratch('/tmp', '128Mi')
  + kurly.config({
    // The data plane is told to take its configuration from the YAML file rather
    // than from etcd; without this it starts, fails to reach an etcd that is not
    // there, and exits.
    'config.yaml': std.manifestYamlDoc({
      deployment: {
        role: 'data_plane',
        role_data_plane: { config_provider: 'yaml' },
      },
      apisix: { node_listen: [9080] },
    } + config, quote_keys=false),
    'apisix.yaml': std.manifestYamlDoc({ routes: routes } + objects, quote_keys=false) + '\n#END\n',
  }, mountPath='/usr/local/apisix/conf', subPath=true)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
