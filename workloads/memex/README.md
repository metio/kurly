<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# memex

[memEx](https://codeberg.org/shibao/memEx) — a structured personal knowledge base
of notes, contexts and pipelines, inspired by zettelkasten and org-mode. A plain
composable `kurly.http` workload on the official image: a Phoenix release on
`:4000` with all of its state in an external PostgreSQL, so it claims no volume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local memex = import 'github.com/metio/kurly/workloads/memex/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='memex-db', database='memex'),
  memex(host='memex.example.com', smtpHost='smtp.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `memex` | |
| `image` | the pinned default | |
| `host` | `localhost` | the public domain links and invite mails are built from |
| `secretName` | `memex` | Secret with `SECRET_KEY_BASE`, `DATABASE_URL`, `SMTP_USERNAME`, `SMTP_PASSWORD` (envFrom) |
| `smtpHost` / `smtpPort` / `smtpSsl` | `localhost` / `587` / `false` | the mail relay |
| `emailFrom` / `emailName` | derived from `host` / `memEx` | sender address and display name |
| `registration` | `invite` | or `public` |
| `locale` | `en_US` | |
| `poolSize` / `replicas` | `10` / `1` | |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:4000` — compose an exposure onto it.

## Database

The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `memex-db`. A
migrator sits in the supervision tree, so the release migrates on start and a
first boot against a fresh database is slower than the ones after it — that is
what the startup probe's budget is for. The connection string carries the
password, so `DATABASE_URL` lives in the Secret rather than in `env`.

## Secrets

`SECRET_KEY_BASE` (Phoenix signs the session cookie with it — a value that changes
on every restart signs everybody out), `DATABASE_URL`, `SMTP_USERNAME` and
`SMTP_PASSWORD` are read from the environment. kurly authors **no Secret** —
provide `memex` holding them, pulled in via `envFrom`.

## Mail is not optional

The production configuration refuses to start without `SMTP_HOST`,
`SMTP_USERNAME` and `SMTP_PASSWORD`. memEx invites users by email and confirms
addresses by email, so an instance that cannot send mail cannot admit anybody past
the first account. `smtpHost` carries a placeholder default so a default render
boots; point it at a real relay before anyone signs up.

## Host

`host` is the public domain the app builds its links and its invite mails from. It
defaults to `localhost`, which makes a default render boot and is wrong for every
real deployment.

## Replicas

Stateless, and still **one replica** by default: without libcluster the Phoenix
PubSub is per node, so two pods do not see each other's live updates.

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
metadata: { name: kurly, namespace: memex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-memex, namespace: memex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/memex, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: memex }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-memex, namespace: memex }
spec: { sourceRef: { kind: OCIRepository, name: kurly-memex } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: memex, namespace: memex }
spec:
  serviceAccountName: memex-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/memex/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-memex, importPath: github.com/metio/kurly/workloads/memex }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: memex, namespace: memex }
spec:
  serviceAccountName: memex-deployer
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
        name: memex
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: memex }
```

<!-- END generated: jaas-deploy -->
