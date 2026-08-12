<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gravity

[Gravity](https://gravity.beryju.io) — replicated DNS, DHCP and TFTP for a local
network, backed by an embedded etcd, with a web interface for the zones, records
and leases. A composable `kurly.stateful` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gravity = import 'github.com/metio/kurly/workloads/gravity/server.libsonnet';

kurly.list(gravity(replicas=3, dhcp=true, tftp=true))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gravity` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | etcd peers — odd numbers |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data` |
| `dhcp` | `false` | answer DHCP as well as DNS |
| `tftp` | `false` | serve net-boot images |
| `resources` / `env` / `labels` / `annotations` | | |

Serves the web interface on `:8008`, DNS on `:53`, and DHCP `:67` / TFTP `:69`
when enabled.

## It runs on the node's network, and it has to

DHCP is answered from broadcast traffic that never reaches a pod behind a Service,
so upstream's own compose file runs with host networking and so does this. Two
consequences worth knowing before deploying it:

- The ports it opens **are the node's ports**, so two members cannot share a node.
  Compose an anti-affinity rule.
- Nothing about it is isolated by a Service — what reaches it is whatever reaches
  the node.

kurly drops the pod's own user namespace automatically here, because Kubernetes
forbids one alongside a shared host namespace, and sets `dnsPolicy` to
`ClusterFirstWithHostNet` so the pod can still resolve in-cluster names.

## Serving `:53` and `:67` is the privilege

Both are below 1024, which the dropped-ALL default forbids binding.
`NET_BIND_SERVICE` is granted by name, and the rest of the hardened posture stands
— no root, read-only root filesystem.

## DNS is useful alone; DHCP is not

A single member answering DNS is a working deployment. DHCP wants to be the only
server on its segment, which is a fact about the network rather than about this
workload — so it is off by default, because one turned on by accident breaks a
network. TFTP exists to net-boot the machines DHCP points at.

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
metadata: { name: kurly, namespace: gravity }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gravity, namespace: gravity }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gravity, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gravity }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gravity, namespace: gravity }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gravity } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gravity, namespace: gravity }
spec:
  serviceAccountName: gravity-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gravity/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gravity, importPath: github.com/metio/kurly/workloads/gravity }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gravity, namespace: gravity }
spec:
  serviceAccountName: gravity-deployer
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
        name: gravity
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: gravity }
```

<!-- END generated: jaas-deploy -->
