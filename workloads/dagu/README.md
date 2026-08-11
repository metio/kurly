<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dagu

[Dagu](https://dagu.sh) — a workflow engine that runs DAGs declared in YAML, with
a web UI to launch, watch and retry them. A plain composable `kurly.http`
workload: DAG definitions, run history and logs are files under `DAGU_HOME` on a
PersistentVolume, so it needs no external database or queue.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dagu = import 'github.com/metio/kurly/workloads/dagu/server.libsonnet';

kurly.list(dagu())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dagu` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | DAGs, run history and logs (`/var/lib/dagu`) |
| `env` | `{}` | any other `DAGU_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Entrypoint

The image's entrypoint runs as root to reconcile the `dagu` user's uid with
`PUID`/`PGID` and then drops privileges with `sudo`, which needs a writable
`/etc` and a root container. This stage calls the `dagu` binary directly instead,
so the hardened posture stands: unprivileged uid, read-only root filesystem, all
capabilities dropped. `fsGroup` is what makes `DAGU_HOME` writable, taking over
the job the entrypoint's `chown` was doing.

## What a step can reach

`dagu start-all` is the scheduler and the web server in one process, and DAG steps
execute as child processes in this container — so a step can only use what the
image ships. Steps that need their own tools belong in Dagu's Kubernetes or SSH
executors rather than in a larger image here.

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
metadata: { name: kurly, namespace: dagu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dagu, namespace: dagu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dagu, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dagu }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dagu, namespace: dagu }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dagu } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dagu, namespace: dagu }
spec:
  serviceAccountName: dagu-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/dagu/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dagu, importPath: github.com/metio/kurly/workloads/dagu }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dagu, namespace: dagu }
spec:
  serviceAccountName: dagu-deployer
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
        name: dagu
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: dagu }
```

<!-- END generated: jaas-deploy -->
