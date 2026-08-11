<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# krakend

[KrakenD](https://www.krakend.io) — a stateless API gateway that composes several
backend calls into one endpoint and applies rate limiting, authentication and
response filtering along the way. A plain composable `kurly.http` workload: the
whole gateway is its configuration, rendered as a ConfigMap, so it keeps nothing.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local krakend = import 'github.com/metio/kurly/workloads/krakend/server.libsonnet';

kurly.list(krakend(endpoints=[{
  endpoint: '/catalogue',
  backend: [{ url_pattern: '/products', host: ['http://catalogue:8080'] }],
}]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `krakend` | |
| `image` | the pinned upstream image | |
| `replicas` | `2` | stateless, so scale freely |
| `endpoints` | `[]` | KrakenD endpoint definitions, verbatim |
| `timeout` | `3s` | how long the gateway waits on a backend |
| `config` | `{}` | merged over the rendered `krakend.json` |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves on `:8080` — compose an exposure onto it.

## The configuration is read once, at startup

KrakenD compiles its routes when the process starts and never re-reads the file,
so changing the ConfigMap does nothing until the pods restart. Roll the Deployment
after a change, or nothing visible happens and the old routes keep serving.

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
metadata: { name: kurly, namespace: krakend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-krakend, namespace: krakend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/krakend, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: krakend }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-krakend, namespace: krakend }
spec: { sourceRef: { kind: OCIRepository, name: kurly-krakend } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: krakend, namespace: krakend }
spec:
  serviceAccountName: krakend-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/krakend/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-krakend, importPath: github.com/metio/kurly/workloads/krakend }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: krakend, namespace: krakend }
spec:
  serviceAccountName: krakend-deployer
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
        name: krakend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: krakend }
```

<!-- END generated: jaas-deploy -->
