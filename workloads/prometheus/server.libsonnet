// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// prometheus — a Prometheus server as a prometheus-operator `Prometheus` custom
// resource, plus the cluster-scoped RBAC it scrapes with. Like cnpg-cluster, this
// authors a CR directly (rather than composing a kurly base kind): the
// prometheus-operator reconciles the `Prometheus` object into the StatefulSet,
// pods, and the `prometheus-operated` Service. Import it, adapt with the
// parameters below, and render with kurly.list:
//
//   local prometheus = import 'github.com/metio/kurly/workloads/prometheus/server.libsonnet';
//   kurly.list(prometheus(namespace='monitoring', retention='30d'))
//
// PREREQUISITE: the prometheus-operator (its CRDs and controller) must be
// installed in the cluster.
//
// Query it at http://prometheus-operated.<namespace>.svc:9090 — the headless
// Service the operator creates for every Prometheus in the namespace.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

// The cluster read access Prometheus needs to discover and scrape targets — the
// standard prometheus-operator rule set. Cluster-scoped because a central
// Prometheus watches every namespace.
local scrapeRules = [
  { apiGroups: [''], resources: ['nodes', 'nodes/metrics', 'services', 'endpoints', 'pods'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: [''], resources: ['configmaps'], verbs: ['get'] },
  { apiGroups: ['discovery.k8s.io'], resources: ['endpointslices'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['networking.k8s.io'], resources: ['ingresses'], verbs: ['get', 'list', 'watch'] },
  { nonResourceURLs: ['/metrics'], verbs: ['get'] },
];

function(
  name='prometheus',
  // Where this Prometheus is deployed. It is stamped on the namespaced objects
  // and, crucially, names the ServiceAccount in the cluster RoleBinding — which a
  // cluster-scoped object cannot inherit later — so it MUST match the namespace
  // you deploy to. Defaults to the conventional 'monitoring'.
  namespace='monitoring',
  image='docker.io/prom/prometheus:v3.13.1',
  replicas=1,
  retention='15d',
  storageSize='50Gi',
  storageClass=null,
  scrapeInterval='30s',
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '2Gi' } },
  externalLabels={},
  // The selectors deciding which ServiceMonitors/PodMonitors/rules/probes this
  // Prometheus honours, and in which namespaces — passed VERBATIM (they are the
  // operator's schema). The default is central monitoring: {} matches every
  // object, and {} for the namespace selectors matches every namespace.
  serviceMonitorSelector={},
  podMonitorSelector={},
  ruleSelector={},
  probeSelector={},
  namespaceSelector={},
  labels={},
  annotations={},
  // Extra Prometheus spec fields, merged over the below (thanos, remoteWrite,
  // additionalScrapeConfigs, …). CNPG's `backup` and this share the pattern: the
  // operator's schema is deep, and kurly does not model it.
  spec={},
)
  // The cluster RoleBinding names the ServiceAccount by namespace, and a
  // cluster-scoped object cannot be namespace-stamped by the consumer later — so
  // the namespace has to be known at render.
  assert namespace != null :
         'prometheus: namespace is required — the cluster RoleBinding must name the ServiceAccount by namespace, which a cluster-scoped object cannot inherit later.';
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as
    // cnpg-cluster.
    assert !std.objectHasAll(self, 'config') :
           "prometheus: kurly features do not apply to a custom resource — use this workload's own parameters (resources, storageClass, labels/annotations, the selectors) instead.",

    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: { name: name, namespace: namespace, labels: labelsFor(name) },
    },
    clusterRole: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: { name: name, labels: labelsFor(name) },
      rules: scrapeRules,
    },
    clusterRoleBinding: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: { name: name, labels: labelsFor(name) },
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: name },
      subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
    },
    prometheus: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'Prometheus',
      metadata: std.prune({
        name: name,
        namespace: namespace,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        image: image,
        replicas: replicas,
        retention: retention,
        scrapeInterval: scrapeInterval,
        serviceAccountName: name,
        // EndpointSlices are the current discovery source; the legacy Endpoints
        // role is being retired.
        serviceDiscoveryRole: 'EndpointSlice',
        externalLabels: (if externalLabels == {} then null else externalLabels),
        // Copy the kurly ownership labels onto the pods the operator creates.
        podMetadata: { labels: labelsFor(name) + labels },
        serviceMonitorSelector: serviceMonitorSelector,
        podMonitorSelector: podMonitorSelector,
        ruleSelector: ruleSelector,
        probeSelector: probeSelector,
        serviceMonitorNamespaceSelector: namespaceSelector,
        podMonitorNamespaceSelector: namespaceSelector,
        ruleNamespaceSelector: namespaceSelector,
        probeNamespaceSelector: namespaceSelector,
        resources: resources,
        // The pod-level hardening kurly applies everywhere, expressed in the CR
        // the operator honours; it manages the container securityContext itself.
        securityContext: {
          runAsNonRoot: true,
          runAsUser: 1000,
          runAsGroup: 2000,
          fsGroup: 2000,
          seccompProfile: { type: 'RuntimeDefault' },
        },
        storage: {
          volumeClaimTemplate: {
            spec: std.prune({
              accessModes: ['ReadWriteOnce'],
              resources: { requests: { storage: storageSize } },
              storageClassName: storageClass,
            }),
          },
        },
      }) + spec,
    },
  }
