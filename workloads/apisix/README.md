<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apisix

[Apache APISIX](https://apisix.apache.org/) — an API gateway: routing,
authentication, rate limiting and observability in front of upstream services. A
plain composable `kurly.http` workload in APISIX's standalone mode, where routes
come from a YAML file rather than from etcd.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local apisix = import 'github.com/metio/kurly/workloads/apisix/gateway.libsonnet';

kurly.list(apisix(routes=[{
  uri: '/orders/*',
  upstream: { type: 'roundrobin', nodes: { 'orders:8080': 1 } },
}]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `apisix` | |
| `image` | the pinned upstream image | |
| `replicas` | `2` | stateless, so scale freely |
| `routes` | `[]` | APISIX route definitions, verbatim |
| `objects` | `{}` | upstreams, services, plugin_configs, consumers, global_rules |
| `config` | `{}` | merged over the rendered `config.yaml` |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves proxied traffic on `:9080` — compose an exposure onto it.

## Standalone, so no etcd

APISIX's default deployment keeps its configuration in an etcd cluster and
reloads on change, which is a second stateful system to run and back up. This
stage takes the other supported shape: the data plane reads `apisix.yaml`,
rendered here as a ConfigMap, and that file is the whole configuration. The trade
is that the admin API is not available — routes are changed by rendering again,
which suits a gateway declared alongside the workloads it fronts.

## The file must end with `#END`

APISIX treats that marker as the end of the configuration and ignores a file
without it: no routes, no error worth the name, just a gateway answering 404 for
everything. The stage appends it rather than leaving it to a caller.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: apisix }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-apisix, namespace: apisix }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/apisix, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: apisix }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-apisix, namespace: apisix }
spec: { sourceRef: { kind: OCIRepository, name: kurly-apisix } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: apisix, namespace: apisix }
spec:
  serviceAccountName: apisix-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local gateway = import 'github.com/metio/kurly/workloads/apisix/gateway.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(gateway())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-apisix, importPath: github.com/metio/kurly/workloads/apisix }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: apisix, namespace: apisix }
spec:
  serviceAccountName: apisix-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: gateway
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: apisix
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: apisix }
```

<!-- END generated: jaas-deploy -->
