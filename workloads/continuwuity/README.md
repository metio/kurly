<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# continuwuity

[Continuwuity](https://continuwuity.org/) — a Matrix homeserver written in Rust, the community-driven continuation of conduwuit and Conduit. A `kurly.http` workload on the official image; its embedded RocksDB on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local continuwuity = import 'github.com/metio/kurly/workloads/continuwuity/server.libsonnet';
kurly.list(continuwuity(serverName='matrix.example.com'))
```

The `serverName` is **baked into every user and room id at first start and cannot be changed** — set it deliberately, and make it reachable per the Matrix well-known/SRV rules. Settings come from the environment under the `CONDUWUIT_` prefix the fork inherited, so `env` takes those names. Service links are off: the injected `CONTINUWUITY_PORT` is a `tcp://` URL the binary would read as its listen port.

Data at `/var/lib/conduwuit` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8008`.

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
metadata: { name: kurly, namespace: continuwuity }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-continuwuity, namespace: continuwuity }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/continuwuity, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: continuwuity }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-continuwuity, namespace: continuwuity }
spec: { sourceRef: { kind: OCIRepository, name: kurly-continuwuity } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: continuwuity, namespace: continuwuity }
spec:
  serviceAccountName: continuwuity-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/continuwuity/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-continuwuity, importPath: github.com/metio/kurly/workloads/continuwuity }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: continuwuity, namespace: continuwuity }
spec:
  serviceAccountName: continuwuity-deployer
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
        name: continuwuity
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: continuwuity }
```

<!-- END generated: jaas-deploy -->
