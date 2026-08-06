<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# yopass

[Yopass](https://github.com/jhaals/yopass) — share a secret through a one-time,
self-destructing encrypted link. The browser encrypts before upload and decrypts after
download, so the server only ever holds ciphertext, and the ciphertext is deleted the
moment it is read once or its expiry passes.

A plain composable `kurly.http` workload on the official image, backed by an external
Redis. Nothing is written to disk, so this is a **stateless** Deployment that scales
horizontally; everything worth keeping lives in the cache, which means a cache that is
flushed loses the secrets nobody had fetched yet — which is the intended lifetime of
the data, not a gap.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local yopass = import 'github.com/metio/kurly/workloads/yopass/server.libsonnet';
kurly.list(yopass())
```

Pairs with a valkey named `yopass-cache`; point `redisHost` elsewhere to use a cache you
already run. Every setting the binary has is a flag rather than an environment variable,
so the stage renders the backend selection into `args`.

Serves the app and its API on `:1337` — compose an exposure onto it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

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
metadata: { name: kurly, namespace: yopass }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-yopass, namespace: yopass }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/yopass, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: yopass }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-yopass, namespace: yopass }
spec: { sourceRef: { kind: OCIRepository, name: kurly-yopass } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: yopass, namespace: yopass }
spec:
  serviceAccountName: yopass-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/yopass/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-yopass, importPath: github.com/metio/kurly/workloads/yopass }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: yopass, namespace: yopass }
spec:
  serviceAccountName: yopass-deployer
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
        name: yopass
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: yopass }
```

<!-- END generated: jaas-deploy -->
