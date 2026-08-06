<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docassemble

[docassemble](https://docassemble.org/) — an expert system that runs guided
interviews written in YAML and Python and assembles the documents they produce.
A composable `kurly.http` workload running the project's **all-in-one**
container: PostgreSQL, Redis, RabbitMQ, Apache and the background workers are all
inside the one image, so it needs nothing outside the cluster.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local docassemble = import 'github.com/metio/kurly/workloads/docassemble/server.libsonnet';

kurly.list(docassemble(hostname='forms.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `docassemble` | |
| `image` | `docker.io/jhpyle/docassemble:1.9.13` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/usr/share/docassemble/backup` |
| `hostname` | unset | the name browsers reach it by |
| `behindHttpsLoadBalancer` | `true` | TLS terminated in front of the pod |
| `timezone` | `UTC` | |
| `shutdownGrace` | `300` | seconds the backup dump is given |

## Persistence is the backup directory, not the data directories

The container writes its database, its Redis snapshot, its configuration and its
uploaded files into `/usr/share/docassemble/backup` as it shuts down, and
restores all of them from there when it starts — that mechanism exists because
the image is meant to be replaced rather than upgraded in place. So the
PersistentVolume goes there.

Mounting the data directories instead does not work: the Python virtualenv the
server runs from, and the configuration it ships, live in the same tree, and an
empty volume over that tree stops the server from starting at all.

Two consequences worth planning for:

- **`shutdownGrace` has to outlast the dump.** A pod killed before it finishes
  comes back at the last dump that completed. The default is five minutes;
  raise it for an instance with a large database or many uploaded files.
- **A pod that dies without shutting down cleanly does not restore.** The
  container detects that on the next start and keeps what it has rather than
  overwriting it with a stale backup.

## First start is slow

The container initialises PostgreSQL, migrates the schema and compiles its assets
before Apache serves anything — minutes on a cold node, and the image is a large
one to pull. That is why the workload carries a generous `startupProbe` budget
rather than a long liveness delay.

## Change the first account

docassemble creates an initial administrator with the credentials published in
its own documentation. Sign in and change them before the instance is reachable
by anyone else.

## Less hardened, deliberately

`supervisord` starts PostgreSQL, Redis, RabbitMQ, cron, syslog-ng and Apache and
drops each to its own account, which it can only do starting from root; Apache
also binds `:80`. The root filesystem is writable because every one of those
services keeps its state, sockets and logs inside the image's own tree — the
database cluster included, and the server installs interview packages into its
own virtualenv at runtime.

## One replica

The database is inside the pod and the volume is ReadWriteOnce, so this is **one
replica, recreated** (never rolled). To scale the pieces apart, docassemble
supports splitting the roles across containers (`CONTAINERROLE`) — kurly carries
only the all-in-one shape today.

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
metadata: { name: kurly, namespace: docassemble }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-docassemble, namespace: docassemble }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/docassemble, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: docassemble }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-docassemble, namespace: docassemble }
spec: { sourceRef: { kind: OCIRepository, name: kurly-docassemble } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docassemble, namespace: docassemble }
spec:
  serviceAccountName: docassemble-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/docassemble/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docassemble, importPath: github.com/metio/kurly/workloads/docassemble }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: docassemble, namespace: docassemble }
spec:
  serviceAccountName: docassemble-deployer
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
        name: docassemble
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docassemble }
```

<!-- END generated: jaas-deploy -->
