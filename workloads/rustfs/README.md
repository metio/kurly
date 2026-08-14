<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rustfs

[RustFS](https://github.com/rustfs/rustfs) — an S3-compatible object store written in
Rust. Buckets and objects on a PersistentVolume, spoken to over the S3 API by anything
that already speaks it.

A plain composable `kurly.http` workload. One volume holds every bucket, which makes this
a **single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rustfs = import 'github.com/metio/kurly/workloads/rustfs/server.libsonnet';

kurly.list(
  rustfs(secretName='rustfs')
  + kurly.expose.gateway('s3.example.com', 'internal')
)
```

## The default credentials are published

Without a Secret the image starts with `rustfsadmin` / `rustfsadmin` — the same pair on
every deployment anyone has ever run. `secretName` carries `RUSTFS_ACCESS_KEY` and
`RUSTFS_SECRET_KEY`, and an instance anything else can reach needs them set *before* it is
reachable.

## It is a release candidate

Upstream marks distributed mode, lifecycle rules and KMS as under test. What this renders
is the single-node shape they call ready. Weigh that against what you are storing.

## Two ports

`:9000` is the S3 API and the Service's `http` port; `:9001` is the console, published as
the extra port `console`. Clients using virtual-host addressing need a wildcard hostname;
path-style works behind one name.

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
metadata: { name: kurly, namespace: rustfs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-rustfs, namespace: rustfs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/rustfs, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: rustfs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-rustfs, namespace: rustfs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-rustfs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: rustfs, namespace: rustfs }
spec:
  serviceAccountName: rustfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/rustfs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-rustfs, importPath: github.com/metio/kurly/workloads/rustfs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: rustfs, namespace: rustfs }
spec:
  serviceAccountName: rustfs-deployer
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
        name: rustfs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: rustfs }
```

<!-- END generated: jaas-deploy -->
