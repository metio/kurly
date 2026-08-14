<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# varnish

[Varnish Cache](https://varnish-cache.org/) — an HTTP cache that sits in front of
something slower. It holds responses in memory and serves them without waking the backend,
with the caching policy written in VCL.

A plain composable `kurly.http` workload holding nothing that outlives the pod.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local varnish = import 'github.com/metio/kurly/workloads/varnish/cache.libsonnet';

kurly.list(
  varnish(backendHost='app', backendPort=8080)
  + kurly.expose.gateway('www.example.com', parent='public')
)
```

## Size the cache below the memory limit

`size` is what Varnish is told it may use for objects. The pod's memory limit has to be
comfortably larger, because the process needs room for its own working set on top — a
cache sized at the limit is a pod the kernel kills under load rather than one that evicts.
The default here is deliberately small.

## VCL is the configuration

The rendered default does one thing: name the backend. Anything past "cache what the
backend says is cacheable" means supplying `vcl`, which replaces the file wholesale —
there is no sensible half-way merge of somebody else's caching policy.

## A rollout is a cold cache

Nothing is persisted, by design: the volume a cache wants is the memory it already has.
Restarting empties it, so a rollout sends a burst straight to the backend. Replicas do not
share a cache either — each fills its own.

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
metadata: { name: kurly, namespace: varnish }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-varnish, namespace: varnish }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/varnish, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: varnish }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-varnish, namespace: varnish }
spec: { sourceRef: { kind: OCIRepository, name: kurly-varnish } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: varnish, namespace: varnish }
spec:
  serviceAccountName: varnish-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cache = import 'github.com/metio/kurly/workloads/varnish/cache.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cache())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-varnish, importPath: github.com/metio/kurly/workloads/varnish }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: varnish, namespace: varnish }
spec:
  serviceAccountName: varnish-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: cache
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: varnish
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: varnish }
```

<!-- END generated: jaas-deploy -->
