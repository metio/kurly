// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tempo — Grafana Tempo as a tempo-operator `TempoStack` custom resource. One CR
// reconciles the whole distributed tracing backend — the distributor, ingester,
// querier, query-frontend, and compactor — over object storage. Like loki (and
// the same shape as its LokiStack), this authors the CR directly; the
// tempo-operator owns the Deployments, StatefulSets, config, and the Services.
// Import it, adapt with the parameters below, and render with kurly.list:
//
//   local tempo = import 'github.com/metio/kurly/workloads/tempo/server.libsonnet';
//   kurly.list(tempo(storageSecret='tempo-s3'))
//
// PREREQUISITE: the tempo-operator (https://grafana.com/docs/tempo/latest/setup/operator/,
// its CRDs and controller) must be installed.
//
// Tempo keeps its trace blocks in OBJECT STORAGE, named by a Secret you create
// (the operator does not): keys bucket, endpoint, access_key_id,
// access_key_secret. It pairs with the kurly seaweedfs workload — point that
// Secret at its S3 gateway. Send spans to the distributor (OTLP on
// tempo-<name>-distributor:4317/:4318) and read them from Grafana by pointing a
// Tempo datasource at tempo-<name>-query-frontend:3200.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver. (The Tempo image itself is the
// operator's to choose from its TempoStack version, so there is none to pin here.)
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='tempo',
  // The Secret naming the object storage, which you create (the operator does
  // not) with the S3 keys above. Required in practice — a TempoStack with no
  // store does not come up.
  storageSecret='tempo-storage',
  // The per-component PVC (the ingester WAL and the local block cache).
  storageSize='10Gi',
  storageClass=null,
  labels={},
  annotations={},
  // Extra TempoStack spec fields, merged over the below (template per-component
  // replicas/resources, replicationFactor, tenants for multi-tenancy and the
  // gateway, retention, limits, …). The operator's schema is deep; kurly does not
  // model it, the same as loki's and prometheus's `spec`.
  spec={},
)
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as loki,
    // cnpg-cluster, and prometheus.
    assert !std.objectHasAll(self, 'config') :
           "tempo: kurly features do not apply to a custom resource — use this workload's own parameters (storageSecret, storageSize, storageClass, labels/annotations) instead.",

    tempostack: {
      apiVersion: 'tempo.grafana.com/v1alpha1',
      kind: 'TempoStack',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
              // Managed = the operator reconciles the stack (the normal mode, and
              // the CRD's own default); the schema requires it named. Override to
              // Unmanaged through `spec` to freeze the components for manual work.
              managementState: 'Managed',
              storage: { secret: { name: storageSecret, type: 's3' } },
              storageSize: storageSize,
            }
            + (if storageClass == null then {} else { storageClassName: storageClass })
            + spec,
    },
  }
