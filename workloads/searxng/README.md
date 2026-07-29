<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# searxng

[SearXNG](https://github.com/searxng/searxng) — a privacy-respecting, self-hosted
metasearch engine that aggregates results from many search services without tracking you. A
plain composable `kurly.http` workload on the official image; its behaviour is its
`settings.yml`, mounted as a ConfigMap, and it keeps no persistent state of its own.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local searxng = import 'github.com/metio/kurly/workloads/searxng/server.libsonnet';
kurly.list(searxng(baseUrl='https://search.example.com'))
```

`settings` is SearXNG's own `settings.yml`, mounted verbatim — kurly does not model it. Set
`SEARXNG_SECRET` from a Secret via `envFrom` (it overrides `server.secret_key` at runtime);
kurly authors **no Secret**. A busy instance also wants a [Valkey](../valkey/) for the
limiter (`settings.redis.url`). Stateless — scale freely. Serves on `:8080`.

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
metadata: { name: kurly, namespace: searxng }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-searxng, namespace: searxng }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/searxng, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: searxng }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-searxng, namespace: searxng }
spec: { sourceRef: { kind: OCIRepository, name: kurly-searxng } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: searxng, namespace: searxng }
spec:
  serviceAccountName: searxng-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/searxng/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-searxng, importPath: github.com/metio/kurly/workloads/searxng }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: searxng, namespace: searxng }
spec:
  serviceAccountName: searxng-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: searxng
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: searxng }
```

<!-- END generated: jaas-deploy -->
