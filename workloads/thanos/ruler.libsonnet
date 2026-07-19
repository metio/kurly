// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos-ruler — a Thanos Ruler as a prometheus-operator `ThanosRuler` custom
// resource: it loads recording and alerting rules from PrometheusRule objects,
// evaluates them against Thanos Query (not a single Prometheus, so the rules see
// the whole global view), and sends firing alerts to Alertmanager. Like
// alertmanager and prometheus, this authors the CR directly; the operator
// reconciles it into a StatefulSet, pods, and the `thanos-ruler-operated`
// governing Service. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local ruler = import 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet';
//   kurly.list(ruler(
//     queryEndpoints=['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local'],
//     alertmanagersUrl=['http://alertmanager-operated.monitoring.svc:9093'],
//   ))
//
// PREREQUISITE: the prometheus-operator (its CRDs and controller) must be
// installed — the same operator the prometheus and alertmanager workloads need.
//
// The rules it evaluates are ordinary PrometheusRule objects selected by
// ruleSelector/ruleNamespaceSelector; author those separately. Reach the ruler's
// UI/API at thanos-ruler-operated.<namespace>.svc:10902.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='thanos-ruler',
  image='quay.io/thanos/thanos:v0.42.2',
  replicas=1,
  // The Thanos Query endpoints the ruler evaluates rules against — the whole
  // point of a Thanos Ruler over a plain Prometheus rule evaluator. Passed
  // verbatim (the operator's schema); the `dnssrv+` prefix makes the operator
  // resolve the SRV record so every Query replica is used.
  queryEndpoints=[],
  // The Alertmanager targets for firing alerts — plain URLs, no auth. For
  // authenticated or TLS Alertmanagers, leave this empty and reference a Secret
  // you provide through `spec.alertmanagersConfig` (kurly never mints the Secret;
  // fill it with External Secrets Operator — see kurly.externalSecret).
  alertmanagersUrl=[],
  // Which PrometheusRule objects to load, and from which namespaces — passed
  // VERBATIM. {} selects every rule object in every namespace; an ABSENT selector
  // selects none, so these are never pruned.
  ruleSelector={},
  ruleNamespaceSelector={},
  storageSize='5Gi',
  storageClass=null,
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
  // Extra ThanosRuler spec fields, merged over the below (externalPrefix,
  // alertQueryUrl, evaluationInterval, objectStorageConfig, alertmanagersConfig,
  // externalLabels via `labels`, …). The operator's schema is deep; kurly does
  // not model it, the same as prometheus's and alertmanager's `spec`.
  spec={},
)
  // The selectors are NOT std.prune-d: an empty selector means "match every
  // PrometheusRule" while an absent one means "match none", so pruning the {}
  // would silently leave the ruler evaluating nothing. queryEndpoints and
  // alertmanagersUrl ARE dropped when empty — an empty array is a meaningful
  // "no endpoints" the operator would otherwise try to honour.
  local rulerSpec =
    {
      image: image,
      replicas: replicas,
      // Copy the kurly ownership labels onto the pods the operator creates.
      podMetadata: { labels: labelsFor(name) + labels },
      ruleSelector: ruleSelector,
      ruleNamespaceSelector: ruleNamespaceSelector,
      // The pod-level hardening kurly applies everywhere, expressed in the CR the
      // operator honours; it manages the container securityContext itself.
      securityContext: {
        runAsNonRoot: true,
        runAsUser: 1001,
        runAsGroup: 1001,
        fsGroup: 1001,
        seccompProfile: { type: 'RuntimeDefault' },
      },
      // Rule evaluation keeps a local WAL/TSDB, so the ruler is stateful.
      storage: {
        volumeClaimTemplate: {
          spec: {
            accessModes: ['ReadWriteOnce'],
            resources: { requests: { storage: storageSize } },
          } + (if storageClass == null then {} else { storageClassName: storageClass }),
        },
      },
    }
    + (if queryEndpoints == [] then {} else { queryEndpoints: queryEndpoints })
    + (if alertmanagersUrl == [] then {} else { alertmanagersUrl: alertmanagersUrl })
    + spec;

  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as
    // cnpg-cluster, prometheus, and alertmanager.
    assert !std.objectHasAll(self, 'config') :
           "thanos-ruler: kurly features do not apply to a custom resource — use this workload's own parameters (resources, storageClass, labels/annotations, ruleSelector, queryEndpoints, alertmanagersUrl) instead.",

    thanosruler: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ThanosRuler',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: rulerSpec,
    },
  }
