// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// alertmanager — an Alertmanager as a prometheus-operator `Alertmanager` custom
// resource: it receives alerts from a Prometheus, deduplicates and groups them,
// and routes them to receivers (email, Slack, PagerDuty, …). Like prometheus,
// this authors the CR directly (rather than composing a kurly base kind); the
// operator reconciles it into a StatefulSet, pods, and the `alertmanager-operated`
// Service. Import it, adapt with the parameters below, and render with kurly.list:
//
//   local alertmanager = import 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet';
//   kurly.list(alertmanager(replicas=3))
//
// PREREQUISITE: the prometheus-operator (its CRDs and controller) must be
// installed — the same operator the prometheus workload needs.
//
// Wire a Prometheus to it through that workload's `spec` escape:
//   prometheus(spec={ alerting: { alertmanagers: [
//     { namespace: 'monitoring', name: 'alertmanager-operated', port: 'web' } ] } })
// Routing and receivers come from AlertmanagerConfig objects it selects (see
// alertmanagerConfigSelector); with none, the operator runs a null default.
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
  name='alertmanager',
  image='docker.io/prom/alertmanager:v0.33.1',
  replicas=1,
  retention='120h',
  storageSize='1Gi',
  storageClass=null,
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  // Which AlertmanagerConfig objects supply the routing/receivers, and in which
  // namespaces — passed VERBATIM (the operator's schema). {} selects every object
  // in every namespace; an ABSENT selector selects none, so these are never
  // pruned.
  alertmanagerConfigSelector={},
  namespaceSelector={},
  labels={},
  annotations={},
  // Extra Alertmanager spec fields, merged over the below (an explicit config
  // secret, clusterGossip settings, externalUrl, …). The operator's schema is
  // deep; kurly does not model it, the same as prometheus's `spec`.
  spec={},
)
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as
    // cnpg-cluster and prometheus.
    assert !std.objectHasAll(self, 'config') :
           "alertmanager: kurly features do not apply to a custom resource — use this workload's own parameters (resources, storageClass, labels/annotations, alertmanagerConfigSelector) instead.",

    alertmanager: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'Alertmanager',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      // NOT std.prune-d: an empty selector means "match every AlertmanagerConfig"
      // while an absent one means "match none" — pruning the {} would silently
      // leave the Alertmanager with no routing. Only optional fields are dropped,
      // by hand (here, the storageClassName when null).
      spec: {
        image: image,
        replicas: replicas,
        retention: retention,
        // Copy the kurly ownership labels onto the pods the operator creates.
        podMetadata: { labels: labelsFor(name) + labels },
        alertmanagerConfigSelector: alertmanagerConfigSelector,
        alertmanagerConfigNamespaceSelector: namespaceSelector,
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
            spec: {
              accessModes: ['ReadWriteOnce'],
              resources: { requests: { storage: storageSize } },
            } + (if storageClass == null then {} else { storageClassName: storageClass }),
          },
        },
      } + spec,
    },
  }
