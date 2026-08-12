<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# percona-server

[Percona Server for MySQL](https://www.percona.com/software/mysql-database/percona-server)
— a drop-in MySQL replacement with the instrumentation and storage-engine work
Percona adds on top: better diagnostics, an audit plugin, and XtraDB. A
composable `kurly.stateful` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local percona = import 'github.com/metio/kurly/workloads/percona-server/server.libsonnet';

kurly.list(percona(database='app', user='app', secretName='percona-server'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `percona-server` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | the data directory |
| `database` / `user` | none | created on first start |
| `secretName` | `percona-server` | `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` |
| `config` | `{}` | merged into a `my.cnf` fragment |
| `resources` / `env` / `labels` / `annotations` | | |

Serves MySQL on `:3306` and the X protocol on `:33060`.

## One server, not a cluster

This is a single `mysqld` with its own volume. It has no replication, no failover
and no automatic backup, so losing the node it is on means restoring from whatever
somebody else took:

```jsonnet
percona(secretName='percona-server') + kurly.backup.volsync(repository='percona-repo')
```

Reach for an operator when the database matters more than the simplicity does.
One replica: raising it makes several unrelated databases, not a cluster.

## The root password is read once

The entrypoint initialises the data directory on first start using the Secret's
values and then never looks at them again. Changing `MYSQL_ROOT_PASSWORD` later
changes nothing, because the credential lives in the database from then on. That
is the usual surprise with this image, and it is not a kurly behaviour.

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
metadata: { name: kurly, namespace: percona-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-percona-server, namespace: percona-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/percona-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: percona-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-percona-server, namespace: percona-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-percona-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: percona-server, namespace: percona-server }
spec:
  serviceAccountName: percona-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/percona-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-percona-server, importPath: github.com/metio/kurly/workloads/percona-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: percona-server, namespace: percona-server }
spec:
  serviceAccountName: percona-server-deployer
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
        name: percona-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: percona-server }
```

<!-- END generated: jaas-deploy -->
