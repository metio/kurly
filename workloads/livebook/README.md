<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# livebook

[Livebook](https://github.com/livebook-dev/livebook) — interactive and
collaborative code notebooks for Elixir. A plain composable `kurly.http` workload
on the official image: the notebooks, and the hubs and secrets Livebook remembers,
live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local livebook = import 'github.com/metio/kurly/workloads/livebook/server.libsonnet';

kurly.list(livebook())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `livebook` | |
| `image` | `ghcr.io/livebook-dev/livebook:0.19.8` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | notebooks and configuration (`/data`) |
| `secretName` | `livebook` | Secret with `LIVEBOOK_PASSWORD` and `LIVEBOOK_SECRET_KEY_BASE` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the notebook UI on `:8080` — compose an exposure onto it.

## Anyone who signs in has a shell in your cluster

A notebook runs arbitrary Elixir — and through it arbitrary commands — **inside
this pod**, with its network access and its volume. Treat access to a Livebook the
way you would treat access to a node: put it behind whatever you use to
authenticate people, keep it off the public internet unless you mean it, and give
the pod only the egress its notebooks actually need.

## Auth and persistence

Without `LIVEBOOK_PASSWORD` Livebook mints a one-time token, prints it into the pod
log and accepts nothing else — so the link everyone holds stops working the moment
the pod is replaced. kurly authors **no Secret**: provide `livebook` holding
`LIVEBOOK_PASSWORD` (at least 12 characters) and `LIVEBOOK_SECRET_KEY_BASE` (at
least 64), pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)).

`LIVEBOOK_HOME` and `LIVEBOOK_DATA_PATH` both point at the volume, so notebooks and
configured hubs survive a restart; `HOME` is a scratch, because a notebook
installing a dependency writes its mix and hex caches there and they are worth
nothing after the pod is gone. The notebooks are on a ReadWriteOnce volume, so this
is **one replica, recreated**.

## A slow first start

The BEAM boots and compiles the notebook runtime before it serves, so the stage
carries a startup probe with a five-minute budget rather than a long liveness
delay. Raise it if you mount large notebooks that pull dependencies at boot.

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
metadata: { name: kurly, namespace: livebook }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-livebook, namespace: livebook }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/livebook, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: livebook }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-livebook, namespace: livebook }
spec: { sourceRef: { kind: OCIRepository, name: kurly-livebook } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: livebook, namespace: livebook }
spec:
  serviceAccountName: livebook-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/livebook/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-livebook, importPath: github.com/metio/kurly/workloads/livebook }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: livebook, namespace: livebook }
spec:
  serviceAccountName: livebook-deployer
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
        name: livebook
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: livebook }
```

<!-- END generated: jaas-deploy -->
