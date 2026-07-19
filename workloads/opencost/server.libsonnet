// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// opencost — OpenCost, the CNCF cost-monitoring model: it reads resource usage
// from Prometheus, joins it with on-prem/cloud pricing, and exposes per-workload
// cost metrics (and an API) Prometheus scrapes back and Grafana charts. A plain
// composable kurly.http workload — not an operator custom resource — but one that
// needs CLUSTER read access to attribute cost across every namespace, so it
// carries a ServiceAccount + ClusterRole + ClusterRoleBinding. Import it, point it
// at a Prometheus, and render with kurly.list:
//
//   local opencost = import 'github.com/metio/kurly/workloads/opencost/server.libsonnet';
//   kurly.list(opencost(namespace='opencost',
//                        prometheusEndpoint='http://prometheus-operated.monitoring.svc:9090'))
//
// It pairs with the prometheus (or thanos) workload as its data source, and serves
// its own metrics/API on :9003 for Prometheus to scrape. The web UI is a separate
// image (ghcr.io/opencost/opencost-ui); this is the cost model.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

// The cluster read access OpenCost needs to attribute cost — the workload and
// scheduling objects across every namespace, plus the metrics endpoint. Read-only
// throughout; OpenCost never writes to the cluster.
local costRules = [
  { apiGroups: [''], resources: ['configmaps', 'nodes', 'pods', 'services', 'resourcequotas', 'replicationcontrollers', 'limitranges', 'persistentvolumeclaims', 'persistentvolumes', 'namespaces', 'endpoints'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['apps'], resources: ['daemonsets', 'deployments', 'replicasets', 'statefulsets'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['batch'], resources: ['cronjobs', 'jobs'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['autoscaling'], resources: ['horizontalpodautoscalers'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['policy'], resources: ['poddisruptionbudgets'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['storage.k8s.io'], resources: ['storageclasses'], verbs: ['get', 'list', 'watch'] },
  { nonResourceURLs: ['/metrics'], verbs: ['get'] },
];

function(
  name='opencost',
  // Where OpenCost is deployed. It names the ServiceAccount in the cluster
  // RoleBinding — which a cluster-scoped object cannot inherit later — so it MUST
  // match the namespace you deploy to.
  namespace='opencost',
  image='ghcr.io/opencost/opencost:1.119.2',
  // The Prometheus (or Thanos Query) OpenCost reads usage from. Defaults to the
  // prometheus workload's Service.
  prometheusEndpoint='http://prometheus-operated.monitoring.svc:9090',
  replicas=1,
  // Extra environment for pricing/cloud integration (CLOUD_PROVIDER_API_KEY,
  // CLUSTER_ID, CONFIG_PATH, …), merged over the Prometheus endpoint.
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  assert namespace != null :
         'opencost: namespace is required — the cluster RoleBinding must name the ServiceAccount by namespace, which a cluster-scoped object cannot inherit later.';

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9003)
  + kurly.servicePort(9003)
  + kurly.env({ PROMETHEUS_SERVER_ENDPOINT: prometheusEndpoint } + env)
  // The image ships no non-root user; pin one so the restricted posture admits it.
  + kurly.runAs(1000)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + {
    // Run under a dedicated ServiceAccount (kurly mounts its token) and author the
    // cluster RBAC as owned manifests — the http kind mints only namespaced RBAC,
    // but cost attribution reads cluster-scoped objects (nodes) and every
    // namespace's pods.
    config+:: { serviceAccountName: name },

    ownedManifests+: [
      {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: { name: name, namespace: namespace, labels: labelsFor(name) },
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRole',
        metadata: { name: name, labels: labelsFor(name) },
        rules: costRules,
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRoleBinding',
        metadata: { name: name, labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: name },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
    ],
  }
