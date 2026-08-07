<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# scm-manager

[SCM-Manager](https://www.scm-manager.org/) — shares and manages Git, Mercurial
and Subversion repositories over HTTP, with users, groups and permissions in one
place. A plain composable `kurly.http` workload; every repository, plugin and
setting lives in `SCM_HOME` on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local scmmanager = import 'github.com/metio/kurly/workloads/scm-manager/server.libsonnet';

kurly.list(scmmanager())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `scm-manager` | |
| `image` | `scmmanager/scm-manager:3.9.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/var/lib/scm` |
| `env` / `resources` / `labels` / `annotations` | | |

## One port carries everything

The web UI, the REST API and all three repository protocols are served on
`:8080`. Compose an exposure onto it and clients clone over that same host — no
extra Service port, no SSH endpoint.

## Finish the setup before it is reachable

The first start brings up a setup screen that creates the administrator account,
and the instance stays open until somebody completes it. On an address reachable
from the internet that is whoever arrives first, so complete the setup — or keep
the exposure off — until an administrator exists.

## Persistence

Repositories, plugins and configuration all live in one directory on a
ReadWriteOnce volume, so this is **one replica, recreated** (never rolled). Two
servers writing the same repository directory is not something git, Mercurial or
Subversion will sort out afterwards.

The plugin cache and the JVM's temporary files sit on scratch volumes beside the
read-only root filesystem; they are rebuilt on every start and hold nothing worth
keeping.

## Slow first start

A first boot unpacks and links the bundled plugins before anything answers, which
takes minutes on a small node. That is why the startup probe allows ten minutes
and why every probe checks the connection rather than a path: until an
administrator exists, each HTTP path either redirects into the setup screen or
answers `401`.

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
metadata: { name: kurly, namespace: scm-manager }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-scm-manager, namespace: scm-manager }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/scm-manager, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: scm-manager }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-scm-manager, namespace: scm-manager }
spec: { sourceRef: { kind: OCIRepository, name: kurly-scm-manager } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: scm-manager, namespace: scm-manager }
spec:
  serviceAccountName: scm-manager-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/scm-manager/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-scm-manager, importPath: github.com/metio/kurly/workloads/scm-manager }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: scm-manager, namespace: scm-manager }
spec:
  serviceAccountName: scm-manager-deployer
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
        name: scm-manager
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: scm-manager }
```

<!-- END generated: jaas-deploy -->
