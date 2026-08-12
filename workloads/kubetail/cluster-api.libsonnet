// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kubetail/cluster-api — the middle of Kubetail's three pieces: the dashboard
// asks it for logs, and it asks the per-node agents. A composable kurly.http
// workload holding no state. Import it and render alongside the dashboard and the
// agent.
//
// Serves its API on :8080. This is an INTERNAL endpoint — the dashboard talks to
// it over the cluster network, and nothing outside needs to reach it.
//
// IT IS THE PIECE THAT ACTUALLY READS THE LOGS, so its grant is the one worth
// looking at: pods/log across the cluster. That is every line every workload
// prints, which is why the three pieces are split — the dashboard can be exposed
// while this one stays inside.
//
// Stateless: no volume, and any replica count is safe.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './cluster-api.image', '\n');

function(
  name='kubetail-cluster-api',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='kubetail',
  replicas=1,
  // The headless Service naming the per-node agents it fans out to.
  clusterAgentHost='kubetail-cluster-agent-headless',
  clusterAgentPort=50051,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({
    KUBETAIL_CLUSTER_API_ADDR: ':8080',
    KUBETAIL_CLUSTER_AGENT_DISPATCH_URL: 'kubernetes://' + clusterAgentHost + ':' + clusterAgentPort,
  } + env)
  // pods/log is the whole point and the whole risk: every line every workload on
  // the cluster prints. Read-only, and cluster-wide because logs are.
  + kurly.clusterRbac(
    [
      { apiGroups: [''], resources: ['namespaces', 'nodes', 'pods', 'pods/log'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['apps'], resources: ['daemonsets', 'deployments', 'replicasets', 'statefulsets'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['batch'], resources: ['cronjobs', 'jobs'], verbs: ['get', 'list', 'watch'] },
    ],
    namespace=namespace
  )
  // The image runs as root and owns nothing that needs it.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
