<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openbao

[OpenBao](https://openbao.org/) — identity-based secrets and encryption
management, the community fork of Vault. A plain composable `kurly.http`
workload using the file storage backend on a PersistentVolume, so a single node
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openbao = import 'github.com/metio/kurly/workloads/openbao/server.libsonnet';

kurly.list(openbao(apiAddr='https://bao.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `openbao` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the file storage backend (`/openbao/file`) |
| `apiAddr` | none | the address clients and other nodes reach the server at |
| `config` | `{}` | merged over the rendered configuration |
| `resources` / `labels` / `annotations` | | |

Serves the API and UI on `:8200` — compose an exposure onto it.

## It starts sealed

A fresh server has no root key and no unseal keys until somebody runs
`bao operator init`, and it seals again on every restart until somebody unseals
it. So the probes here are by connection: an HTTP health check reports 501
uninitialised and 503 sealed, and a liveness probe reading those would restart a
server that is behaving exactly as designed, forever. Expect to unseal after a
rollout.

## TLS and memory locking

`tls_disable` is set on the listener, because a cluster deployment terminates TLS
at the exposure in front of it and OpenBao would otherwise want a certificate
before it will answer at all. Traffic between the pod and that exposure is
plaintext inside the cluster — compose a service mesh onto this if that is not
acceptable, or pass a listener of your own through `config`.

`disable_mlock` is set, so the process does not need the `IPC_LOCK` capability
the hardened default drops. The trade is that secrets in memory may be swapped to
disk; on a node with swap off there is nothing to swap to.

Single writer: the file backend is one directory on a ReadWriteOnce volume, so one
replica, recreated. Raft (`storage "raft"` through `config`, on a stateful set) is
what more than one node needs.

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
metadata: { name: kurly, namespace: openbao }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-openbao, namespace: openbao }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/openbao, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: openbao }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-openbao, namespace: openbao }
spec: { sourceRef: { kind: OCIRepository, name: kurly-openbao } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: openbao, namespace: openbao }
spec:
  serviceAccountName: openbao-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/openbao/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-openbao, importPath: github.com/metio/kurly/workloads/openbao }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: openbao, namespace: openbao }
spec:
  serviceAccountName: openbao-deployer
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
        name: openbao
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: openbao }
```

<!-- END generated: jaas-deploy -->
