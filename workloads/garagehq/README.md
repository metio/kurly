<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# garagehq

[Garage](https://garagehq.deuxfleurs.fr/) as a **stateful S3 node** — the
`kurly.stateful` shape, a StatefulSet with a per-pod PVC and a headless Service.
It gives a cluster an S3 API on `3900`, a static-website server on `3902`, an
admin API on `3903`, and the node-to-node RPC port on `3901`.

Garage is written for copies that live in **different buildings**: it assumes the
links between its nodes are slow and occasionally gone, which is a different
design point from a store built for one rack.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local garage = import 'github.com/metio/kurly/workloads/garagehq/server.libsonnet';

kurly.list(garage(storageSize='100Gi', storageClass='fast'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `garage` | also names the headless Service |
| `storageSize` | `20Gi` | metadata and data, mounted at `/var/lib/garage` |
| `storageClass` | cluster default | |
| `replicationFactor` | `1` | copies of every object; the layout must be able to meet it |
| `s3Region` | `garage` | the region name S3 clients have to send |
| `s3RootDomain` | `.s3.garage.localhost` | virtual-host-style bucket addressing |
| `webRootDomain` | `.web.garage.localhost` | the same for the website server |
| `secretName` | `garage` | read with `envFrom` |
| `config` | the generated TOML | replaces `garage.toml` wholesale |

## The Secret

kurly authors no Secret. Garage **refuses to start** without an RPC secret, so
this one has to exist before the pod is scheduled:

| Key | What it is |
|---|---|
| `GARAGE_RPC_SECRET` | 32 bytes as 64 hex characters (`openssl rand -hex 32`) |

Every node of one cluster carries the **same** value — it is how they authenticate
to each other, and changing it partitions them. Any other `GARAGE_*` override an
operator wants (an admin token, a metrics token) rides in the same Secret.

## A Ready pod is not yet a bucket

Garage stores nothing until a **cluster layout** hands the node some capacity, and
that is an operator command against the running pod rather than a manifest:

```shell
kubectl exec garage-0 -- /garage status                        # read the node id
kubectl exec garage-0 -- /garage layout assign -z dc1 -c 100G <id>
kubectl exec garage-0 -- /garage layout apply --version 1
```

Keys and buckets are the same kind of runtime state:

```shell
kubectl exec garage-0 -- /garage key create app
kubectl exec garage-0 -- /garage bucket create backups
kubectl exec garage-0 -- /garage bucket allow --read --write backups --key app
```

The pod is Ready before any of that: the port is open and the layout is empty. No
probe can tell the difference, which is why this is written down rather than
automated away.

## Configuration

One TOML file, mounted by `subPath` at `/etc/garage.toml` so the image's own
`/etc` — the CA bundle included — is not replaced by the mount. Pass `config` to
take the file over entirely.

`rpc_public_addr` is deliberately absent: unset, Garage advertises the address of
its own interface, which in a pod is the routable pod IP. The stable alternative
is the pod's headless DNS record, and that is per-pod — one shared ConfigMap
cannot hold a different address for each replica.

Metadata (an LMDB index of every object) and the data blocks share one volume.
Garage would rather have the metadata on an SSD of its own; that is a second
`kurly.store` a consumer composes, not a default that would ask every cluster for
two volumes.

## Growing it

More replicas is not how Garage grows. A second replica here is a second node in
the same namespace, on the same layout, still keeping `replicationFactor` copies
of every object. A real Garage cluster is **one of these per site**, each in its
own layout zone, which is the arrangement the software exists for.

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
metadata: { name: kurly, namespace: garagehq }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-garagehq, namespace: garagehq }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/garagehq, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: garagehq }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-garagehq, namespace: garagehq }
spec: { sourceRef: { kind: OCIRepository, name: kurly-garagehq } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: garagehq, namespace: garagehq }
spec:
  serviceAccountName: garagehq-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/garagehq/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-garagehq, importPath: github.com/metio/kurly/workloads/garagehq }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: garagehq, namespace: garagehq }
spec:
  serviceAccountName: garagehq-deployer
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
        name: garagehq
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: garagehq }
```

<!-- END generated: jaas-deploy -->
