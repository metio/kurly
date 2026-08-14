<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bifrost

[Bifrost](https://github.com/maximhq/bifrost) — an AI gateway. It puts one
OpenAI-compatible endpoint in front of many model providers, so an application holds one
URL and one key rather than a set that grows with every provider added, and the gateway
handles failover between them, load balancing across them, and budgets per key.

A plain composable `kurly.http` workload on the project's own image. The configuration
and the request logs live in a file database on the volume at `/app/data`, which makes
this a **single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bifrost = import 'github.com/metio/kurly/workloads/bifrost/gateway.libsonnet';

kurly.list(
  bifrost(secretName='bifrost')
  + kurly.expose.gateway('ai.example.com', parent='public')
)
```

## The provider keys

`secretName` names a Secret holding the provider variables the configuration refers to —
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY` and whichever others the deployment uses. kurly
authors none of them: they are billed by the token and belong to whoever pays that bill.

## Reaching it is equivalent to holding those keys

The gateway requires no client key by default. Governance, budgets and virtual keys are
configured through its web interface after the first start, and until that is done
anything that can reach the endpoint can spend against every provider key it carries.
Put it behind authentication before it is reachable from a network you do not control.

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
metadata: { name: kurly, namespace: bifrost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bifrost, namespace: bifrost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bifrost, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bifrost }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bifrost, namespace: bifrost }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bifrost } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bifrost, namespace: bifrost }
spec:
  serviceAccountName: bifrost-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local gateway = import 'github.com/metio/kurly/workloads/bifrost/gateway.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(gateway())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bifrost, importPath: github.com/metio/kurly/workloads/bifrost }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bifrost, namespace: bifrost }
spec:
  serviceAccountName: bifrost-deployer
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
        name: bifrost
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bifrost }
```

<!-- END generated: jaas-deploy -->
