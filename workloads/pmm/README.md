<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pmm

[Percona Monitoring and Management](https://www.percona.com/software/database-tools/percona-monitoring-and-management)
— the server half of a database monitoring system, collecting metrics and query
analytics from agents running beside MySQL, PostgreSQL and MongoDB instances.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pmm = import 'github.com/metio/kurly/workloads/pmm/server.libsonnet';

kurly.list(pmm(secretName='pmm', retention='30d'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pmm` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | everything, under `/srv` |
| `secretName` | none | `PMM_ADMIN_PASSWORD`, read once |
| `retention` | none | how long metrics are kept |
| `resources` / `env` / `labels` / `annotations` | | |

Serves on `:8080` — compose an exposure onto it.

## It is the server, and the agents are somewhere else

PMM sees nothing until a `pmm-agent` is installed beside each database and
registered against this server, which happens from the database's side rather than
from here. A PMM with no agents is a working set of empty dashboards.

## Everything lives in one directory

The image bundles VictoriaMetrics for the metrics, PostgreSQL for its own
inventory and ClickHouse for query analytics, and puts all of them under `/srv` on
one volume. The volume is the whole deployment, and its size is a retention
decision rather than an afterthought.

The admin password is read once, at first start, and lives in PMM's own database
from then on — changing the Secret afterwards changes nothing.

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
metadata: { name: kurly, namespace: pmm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pmm, namespace: pmm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pmm, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pmm }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pmm, namespace: pmm }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pmm } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pmm, namespace: pmm }
spec:
  serviceAccountName: pmm-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pmm/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pmm, importPath: github.com/metio/kurly/workloads/pmm }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pmm, namespace: pmm }
spec:
  serviceAccountName: pmm-deployer
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
        name: pmm
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pmm }
```

<!-- END generated: jaas-deploy -->
