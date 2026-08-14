<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shkeeper

[SHKeeper](https://github.com/vsys-host/shkeeper.io) — a cryptocurrency payment gateway you
run yourself. It watches for payments, credits invoices and calls your shop back, with no
processor between you and the chain.

A plain composable `kurly.http` workload. The database and wallet state share one volume,
which makes this a **single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shkeeper = import 'github.com/metio/kurly/workloads/shkeeper/server.libsonnet';

kurly.list(
  shkeeper(secretName='shkeeper')
  + kurly.expose.gateway('pay.example.com', parent='public')
)
```

## It takes no payments until a node answers it

Every currency needs its own backend — a Bitcoin, Litecoin or Monero daemon with its own
chain data, which is hundreds of gigabytes and days of initial sync. This recipe carries
the gateway and none of those. With no backend configured it starts, serves its interface,
and accepts nothing.

## The credentials are the money

Whatever holds this instance's credentials can move funds. The Secret is the entire
security boundary, and an exposure with nothing authenticating in front of it is an open
till.

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
metadata: { name: kurly, namespace: shkeeper }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-shkeeper, namespace: shkeeper }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/shkeeper, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: shkeeper }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-shkeeper, namespace: shkeeper }
spec: { sourceRef: { kind: OCIRepository, name: kurly-shkeeper } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: shkeeper, namespace: shkeeper }
spec:
  serviceAccountName: shkeeper-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/shkeeper/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-shkeeper, importPath: github.com/metio/kurly/workloads/shkeeper }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: shkeeper, namespace: shkeeper }
spec:
  serviceAccountName: shkeeper-deployer
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
        name: shkeeper
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: shkeeper }
```

<!-- END generated: jaas-deploy -->
