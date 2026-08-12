<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# databasus

[Databasus](https://databasus.com) — scheduled backups for the PostgreSQL, MySQL
and MongoDB databases you already run, with a web interface, restore, and
notifications when a run fails.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local databasus = import 'github.com/metio/kurly/workloads/databasus/server.libsonnet';

kurly.list(databasus(publicUrl='https://backups.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `databasus` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | backups, spool and the embedded database |
| `publicUrl` | none | what notification mails link to |
| `secretName` | none | SMTP credentials, OAuth client secrets |
| `resources` / `env` / `labels` / `annotations` | | |

Serves the web interface on `:4005` — compose an exposure onto it.

## It runs its own PostgreSQL inside the pod

The image starts an embedded PostgreSQL for its own schedules and history, on the
same volume as the backups it takes, and offers no way to point it at an external
database. So one PersistentVolume holds both the backups and the only record of
what was backed up, in the same cluster as the databases it protects — a defence
against a dropped table, not against losing the cluster:

```jsonnet
databasus() + kurly.backup.volsync(repository='databasus-repo')
```

Send the backups off-cluster, or compose a backup axis onto this volume, before
calling it disaster recovery.

## Why four defaults are relaxed

The entrypoint reconciles the embedded postgres user's uid, chowns three
directories under the data volume, and writes the frontend's runtime configuration
into the image tree before starting anything. That needs root, escalation, the
runtime capabilities and a writable root filesystem.

It also holds credentials for everything it backs up, so a NetworkPolicy limiting
its egress to exactly those databases is worth composing on.

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
metadata: { name: kurly, namespace: databasus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-databasus, namespace: databasus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/databasus, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: databasus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-databasus, namespace: databasus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-databasus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: databasus, namespace: databasus }
spec:
  serviceAccountName: databasus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/databasus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-databasus, importPath: github.com/metio/kurly/workloads/databasus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: databasus, namespace: databasus }
spec:
  serviceAccountName: databasus-deployer
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
        name: databasus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: databasus }
```

<!-- END generated: jaas-deploy -->
