<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sablier

[Sablier](https://sablierapp.dev/) — scales workloads to zero and starts them
again on the first request, with a waiting page while they come up. A plain
composable `kurly.http` workload: it watches and scales other workloads through
the Kubernetes API and keeps nothing of its own.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sablier = import 'github.com/metio/kurly/workloads/sablier/server.libsonnet';

kurly.list(sablier(sessionDuration='10m'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sablier` | |
| `image` | the pinned upstream image | |
| `sessionDuration` | `5m` | how long a workload stays awake after the last request |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves its API on `:10000`. Sablier does not proxy traffic itself: a middleware in
Traefik, Caddy, Nginx, Envoy, Istio or APISIX asks it whether the workload is up,
holds the request while it starts, and only then forwards. Expose it only if that
proxy sits outside the cluster.

## The grant

Sablier needs to read and change the replica count of the workloads it manages,
which is a namespace-wide grant on deployments and statefulsets — it cannot be
narrowed to the ones it manages, because RBAC `resourceNames` cannot express
"whichever carry the sablier label". `kurly.apiServerClient` declares that grant
and the egress to the apiserver together, so a consumer's own `rbac()` or
`networkPolicy()` composes with it rather than firewalling the scaler off from
what it scales. The ServiceAccount, Role and RoleBinding are rendered alongside
the Deployment.

## Sessions are in memory

Which workloads are currently awake, and for how much longer, is process state: a
restart forgets it and the next request starts the workload again. That is a slow
first request rather than an error, so there is no volume — and it is why one
replica is the arrangement that behaves predictably, since two pods would each
hold their own idea of what is running.

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
metadata: { name: kurly, namespace: sablier }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sablier, namespace: sablier }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sablier, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sablier }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sablier, namespace: sablier }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sablier } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sablier, namespace: sablier }
spec:
  serviceAccountName: sablier-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sablier/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sablier, importPath: github.com/metio/kurly/workloads/sablier }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sablier, namespace: sablier }
spec:
  serviceAccountName: sablier-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: sablier
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sablier }
```

<!-- END generated: jaas-deploy -->
