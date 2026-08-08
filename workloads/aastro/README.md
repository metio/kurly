<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# aastro

[Aastro](https://github.com/starwalkn/aastro) — an API gateway that matches an
incoming request against a flow, fans it out to the upstreams that flow names
and aggregates their answers into one response. A plain composable `kurly.http`
workload on the official image; its `config.yaml` is the only state it needs,
rendered as a ConfigMap.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local aastro = import 'github.com/metio/kurly/workloads/aastro/server.libsonnet';

kurly.list(
  aastro(flows=[
    {
      path: '/api/hello',
      method: 'GET',
      aggregation: { strategy: 'array', best_effort: false },
      upstreams: [
        { name: 'hello', hosts: 'http://hello.default.svc.cluster.local', path: '/hello', method: 'GET', timeout: '3s' },
      ],
    },
  ])
  + kurly.expose.gateway('api.example.com', 'public')
)
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `aastro` | |
| `image` | `docker.io/starwalkn/aastro:0.8.0` | |
| `replicas` | `2` | stateless, so any count is safe |
| `flows` | `[]` | passed through verbatim |
| `timeout` / `headerTimeout` | `10s` / `5s` | data listener |
| `adminBindAddr` | `0.0.0.0` | see below |
| `gateway` | `{}` | merged over the generated `gateway` section |

## Flows are passed through verbatim

`flows` lands unchanged in `gateway.routing.flows`. kurly does not model
Aastro's flow schema — it would drift against the gateway's own reference, and a
half-modelled schema is worse than none because it rejects configuration the
gateway accepts. Anything else under `gateway` (observability, the rate limiter,
trusted proxies, inbound TLS) goes in the `gateway` parameter, which merges over
what the stage generates.

The default is no flows at all. A gateway with no routes answers its probes and
proxies nothing, which is the honest default: which services to fan a request out
to is not something a recipe can guess.

## Two listeners, and only one is for callers

Proxied traffic arrives on `:7805`. Health, readiness, Prometheus metrics and the
diagnostics live on a separate **admin** listener, `:7806`. Aastro binds that
listener to `127.0.0.1` by default, where a kubelet probe cannot reach it and the
pod never turns ready — so the stage writes `bind_addr` explicitly. Keep the
admin port off any exposure unless the diagnostics are meant to be public.

Probes read `/__ready` and `/__health` on the **admin** port, never the data
port: a request to `:7805` is answered by whatever upstream a flow names, so its
status says nothing about the gateway itself.

## No Secret, no volume

Nothing in the configuration is a credential, so kurly authors no Secret. Routing
lives entirely in the configuration and nothing is kept between requests, so
there is no PersistentVolume and no single-writer constraint.

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
metadata: { name: kurly, namespace: aastro }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-aastro, namespace: aastro }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/aastro, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: aastro }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-aastro, namespace: aastro }
spec: { sourceRef: { kind: OCIRepository, name: kurly-aastro } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: aastro, namespace: aastro }
spec:
  serviceAccountName: aastro-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/aastro/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-aastro, importPath: github.com/metio/kurly/workloads/aastro }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: aastro, namespace: aastro }
spec:
  serviceAccountName: aastro-deployer
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
        name: aastro
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: aastro }
```

<!-- END generated: jaas-deploy -->
