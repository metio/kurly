// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// loki — Grafana Loki in microservices mode as a loki-operator `LokiStack`
// custom resource. One CR reconciles the whole distributed topology — the
// distributor, ingester, querier, query-frontend, compactor, index-gateway, and
// gateway — with `size` choosing the replica scaling. Like cnpg-cluster and
// prometheus, this authors the CR directly (rather than hand-wiring the
// components); the loki-operator owns the Deployments, StatefulSets, config, and
// the memberlist ring. Import it, adapt with the parameters below, and render
// with kurly.list:
//
//   local loki = import 'github.com/metio/kurly/workloads/loki/server.libsonnet';
//   kurly.list(loki(size='1x.small', storageSecret='loki-s3'))
//
// PREREQUISITE: the loki-operator (https://loki-operator.dev, its CRDs and
// controller) must be installed.
//
// Loki keeps its chunks and index in OBJECT STORAGE, named by a Secret you
// create (the operator does not): keys bucketnames, endpoint, access_key_id,
// access_key_secret, region. It pairs with the kurly seaweedfs workload — point
// that Secret at its S3 gateway. Reach Loki at the operator's gateway Service,
// lokistack-gateway-http.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver. (The Loki image itself is the
// operator's to choose from its LokiStack version, so there is none to pin here.)
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='loki',
  // The t-shirt size the operator scales the components to. 1x.demo is the
  // smallest — single replicas, minimal resources — and the right one for a test
  // cluster; production wants 1x.extra-small or larger.
  size='1x.demo',
  // The Secret naming the object storage, which you create (the operator does
  // not) with the S3 keys above. Required in practice — a LokiStack with no store
  // does not come up.
  storageSecret='loki-storage',
  storageClass=null,
  // The index schema. v13 with a tsdb store is the current recommendation; add
  // rows here (never edit an existing one) to migrate the schema forward.
  schemaVersion='v13',
  schemaEffectiveDate='2024-01-01',
  labels={},
  annotations={},
  // Extra LokiStack spec fields, merged over the below (tenants, replication,
  // per-component template overrides, limits, …). The operator's schema is deep;
  // kurly does not model it, the same as cnpg's `backup` and prometheus's `spec`.
  spec={},
)
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as
    // cnpg-cluster and prometheus.
    assert !std.objectHasAll(self, 'config') :
           "loki: kurly features do not apply to a custom resource — use this workload's own parameters (size, storageSecret, storageClass, labels/annotations) instead.",

    lokistack: {
      apiVersion: 'loki.grafana.com/v1',
      kind: 'LokiStack',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
              size: size,
              storage: {
                secret: { name: storageSecret, type: 's3' },
                schemas: [{ version: schemaVersion, effectiveDate: schemaEffectiveDate }],
              },
            }
            + (if storageClass == null then {} else { storageClassName: storageClass })
            + spec,
    },
  }
