<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hypermind

[Hypermind](https://github.com/lklynet/hypermind) — a peer-to-peer deployment counter and
ephemeral chat. Every instance joins a Hyperswarm DHT, finds the others running the same
image, and shows how many there are. Upstream describes it as "the high-availability
solution to a problem that doesn't exist", and this recipe takes it at its word.

A plain composable `kurly.http` workload: no database, no volume, no external service.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hypermind = import 'github.com/metio/kurly/workloads/hypermind/server.libsonnet';

kurly.list(
  hypermind()
  + kurly.expose.gateway('hypermind.example.com', 'public')
)
```

## It dials strangers on the public internet

Finding peers means outbound connections to a distributed hash table. In a cluster with a
default-deny egress policy it has nothing to count; in a cluster without one it holds
connections to peers nobody vetted. Both are the honest outcome of what this is, not a
misconfiguration.

## Replicas are peers, not capacity

Two replicas do not serve twice the traffic — they find each other and the count goes up
by one. Nothing is persisted: messages last as long as a peer is connected, and a restart
starts over.

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
metadata: { name: kurly, namespace: hypermind }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hypermind, namespace: hypermind }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hypermind, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hypermind }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hypermind, namespace: hypermind }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hypermind } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hypermind, namespace: hypermind }
spec:
  serviceAccountName: hypermind-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hypermind/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hypermind, importPath: github.com/metio/kurly/workloads/hypermind }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hypermind, namespace: hypermind }
spec:
  serviceAccountName: hypermind-deployer
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
        name: hypermind
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hypermind }
```

<!-- END generated: jaas-deploy -->
