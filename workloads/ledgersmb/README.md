<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ledgersmb

[LedgerSMB](https://github.com/ledgersmb/LedgerSMB) — double-entry accounting and
ERP for small and midsize businesses: receivables, payables, the general ledger,
invoicing, inventory and fixed assets, served as a Perl/starman web application.
A plain composable `kurly.http` workload backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ledgersmb = import 'github.com/metio/kurly/workloads/ledgersmb/server.libsonnet';

kurly.list(ledgersmb())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ledgersmb` | |
| `image` | `docker.io/ledgersmb/ledgersmb:1.13` | |
| `dbHost` / `dbPort` | `ledgersmb-db-rw` / `5432` | pairs with a `cnpg-cluster` named `ledgersmb-db` |
| `database` | `lsmb` | the company database offered on the login screen |
| `proxyIp` | `10.0.0.0/8` | which clients may set `X-Forwarded-For` |
| `workers` | `5` | starman workers, i.e. concurrent requests per pod |

## Setup is a web step, not an env contract

LedgerSMB has no application-level database credentials, which is why this
workload reads no Secret — there is nothing kurly could put in one. Instead an
operator visits `/setup.pl`, logs in with a **PostgreSQL superuser**, and creates
each company database from there; users afterwards log in with their own
PostgreSQL roles. Point `dbHost` at a cluster whose superuser you hold and expose
`/setup.pl` no wider than you have to.

## No volume

Every company's books, documents and attachments live in PostgreSQL. This stage
claims no PersistentVolume: nothing on the pod survives a restart and nothing
needs to. Back up the database, not the workload.

The root filesystem stays read-only. Two scratch volumes carry what the container
genuinely writes — `/tmp`, where the entrypoint generates `ledgersmb.conf` and the
LaTeX document path works, and `/srv/ledgersmb/local`, the application's own
writable tree. The image already runs as `www-data`, so no privilege relaxation is
needed.

## Probes and links

Both probes ask for a **connection**, not a status: an instance with no company
database yet answers a redirect or a 401 on every path, and a probe reading that
as failure would kill the pod before anyone could run setup.

Service links are disabled deliberately: a Service named `postgres` in the same
namespace injects `POSTGRES_PORT=tcp://…`, which the entrypoint would copy
straight into the database port of the generated configuration.

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
metadata: { name: kurly, namespace: ledgersmb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ledgersmb, namespace: ledgersmb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ledgersmb, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ledgersmb }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ledgersmb, namespace: ledgersmb }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ledgersmb } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ledgersmb, namespace: ledgersmb }
spec:
  serviceAccountName: ledgersmb-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ledgersmb/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ledgersmb, importPath: github.com/metio/kurly/workloads/ledgersmb }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ledgersmb, namespace: ledgersmb }
spec:
  serviceAccountName: ledgersmb-deployer
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
        name: ledgersmb
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ledgersmb }
```

<!-- END generated: jaas-deploy -->
