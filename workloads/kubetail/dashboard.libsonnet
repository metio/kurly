// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kubetail/dashboard — a web interface for tailing the logs of many pods at once,
// across deployments and namespaces, with search and live follow. A composable
// kurly.http workload holding no state. Import it and render alongside the other
// two stages:
//
//   local dashboard = import 'github.com/metio/kurly/workloads/kubetail/dashboard.libsonnet';
//   local api = import 'github.com/metio/kurly/workloads/kubetail/cluster-api.libsonnet';
//   local agent = import 'github.com/metio/kurly/workloads/kubetail/cluster-agent.libsonnet';
//   kurly.list([dashboard(), api(), agent()])
//
// Serves the dashboard on :8080 — compose an exposure onto it.
//
// THREE PIECES, AND THE LOGS COME FROM THE LAST ONE. The dashboard is the browser
// front end, cluster-api is what it asks, and the cluster-agent is a DaemonSet
// that reads the log files off each node. Deploy all three: a dashboard alone
// lists workloads and shows no logs, which looks like a broken cluster rather
// than a missing component.
//
// IT SHOWS LOG LINES FROM EVERY NAMESPACE IT IS ALLOWED TO READ. Whoever reaches
// this page reads whatever the workloads on the cluster print, which routinely
// includes tokens, query parameters and personal data nobody meant to publish.
// Put authentication in front of it.
//
// Stateless: no volume, and any replica count is safe.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './dashboard.image', '\n');

function(
  name='kubetail-dashboard',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='kubetail',
  replicas=1,
  // The cluster-api stage this asks for logs.
  clusterApiHost='kubetail-cluster-api',
  clusterApiPort=8080,
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
    KUBETAIL_DASHBOARD_ADDR: ':8080',
    KUBETAIL_CLUSTER_API_ENDPOINT: 'http://' + clusterApiHost + ':' + clusterApiPort,
  } + env)
  // Reading what workloads exist, so the dashboard can offer them. The LOG
  // CONTENT does not come through here — that is the cluster-api's grant.
  + kurly.clusterRbac(
    [
      { apiGroups: [''], resources: ['namespaces', 'nodes', 'pods'], verbs: ['get', 'list', 'watch'] },
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
