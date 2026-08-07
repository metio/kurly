<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mindwendel

[mindwendel](https://github.com/b310-digital/mindwendel) — a shared brainstorming
board where a team collects ideas and upvotes them. A plain composable
`kurly.http` workload on the official image: a Phoenix release on `:4000` with its
state in an external PostgreSQL and nothing on disk.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mindwendel = import 'github.com/metio/kurly/workloads/mindwendel/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='mindwendel-db', database='mindwendel'),
  mindwendel(urlHost='ideas.example.com', urlPort='443', urlScheme='https'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mindwendel` | |
| `image` | the pinned default | |
| `dbHost` / `dbName` / `dbUser` / `dbPort` | `mindwendel-db-rw` / `mindwendel` / `mindwendel` / `5432` | |
| `databaseSsl` | `false` | speak TLS to the database |
| `urlHost` / `urlPort` / `urlScheme` | `localhost` / `4000` / `http` | the public URL board links are built from |
| `secretName` | `mindwendel` | Secret with `SECRET_KEY_BASE` and `DATABASE_USER_PASSWORD` (envFrom) |
| `defaultLocale` / `removalAfterDays` | `en` / `30` | `''` keeps boards forever |
| `fileUpload` | `false` | attachments; needs object storage and a vault key |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the board on `:4000` — compose an exposure onto it.

## Database

The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `mindwendel-db`.
The entrypoint waits for the server to answer, runs the Ecto migrations, and only
then starts Phoenix, so a first boot takes a while — that is what the startup
probe's budget is for.

`databaseSsl` is off by default because an in-namespace PostgreSQL commonly serves
plaintext and the app refuses to connect when it is told to expect TLS that is not
there. Turn it on once the server has a certificate.

## Secrets

`SECRET_KEY_BASE` (Phoenix signs sessions with it — sessions and stored data
depend on it staying stable) and `DATABASE_USER_PASSWORD` are read from the
environment. kurly authors **no Secret** — provide `mindwendel` holding both,
pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)).

## File uploads

Off by default. Turning them on is not a flag on its own: attachments are stored
in S3-compatible object storage and encrypted with a vault key, so `fileUpload=true`
also needs the `OBJECT_STORAGE_*` settings in `env` and a base64
`VAULT_ENCRYPTION_KEY_BASE64` in the Secret. Defaulting it on would render a
workload that cannot start.

## Replicas

Stateless, and still **one replica** by default: without libcluster the Phoenix
PubSub is per node, so two pods serve the same board without seeing each other's
ideas.

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
metadata: { name: kurly, namespace: mindwendel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mindwendel, namespace: mindwendel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mindwendel, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mindwendel }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mindwendel, namespace: mindwendel }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mindwendel } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mindwendel, namespace: mindwendel }
spec:
  serviceAccountName: mindwendel-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mindwendel/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mindwendel, importPath: github.com/metio/kurly/workloads/mindwendel }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mindwendel, namespace: mindwendel }
spec:
  serviceAccountName: mindwendel-deployer
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
        name: mindwendel
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mindwendel }
```

<!-- END generated: jaas-deploy -->
