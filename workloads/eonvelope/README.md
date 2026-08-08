<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# eonvelope

[Eonvelope](https://gitlab.com/Dacid99/eonvelope) — a Django application that
fetches mail over IMAP, POP, Exchange or JMAP and keeps it, with its attachments
and correspondents, searchable for as long as you care to keep it. A composable
`kurly.http` workload backed by an **external MySQL/MariaDB**; the archive itself
lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local eonvelope = import 'github.com/metio/kurly/workloads/eonvelope/server.libsonnet';

kurly.list(eonvelope(dbHost='eonvelope-db', allowedHosts='mail.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `eonvelope` | |
| `image` | `dacid99/eonvelope:0.7.2` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/mnt/archive` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `eonvelope-db` / `3306` / `email_archive_django` / `eonvelope` | |
| `databaseType` | `mysql` | also `postgresql`, `sqlite3` |
| `allowedHosts` | `*` | every host the instance answers on, comma separated |
| `secretName` | `eonvelope` | read with `envFrom` |
| `env` / `resources` / `labels` / `annotations` | | |

## It speaks HTTPS, not HTTP

gunicorn binds `:443` with the **self-signed certificate the image bakes in**, so
whatever routes to it has to talk TLS to the backend and must not verify that
certificate against a public CA — a backend-protocol annotation on an Ingress, a
`BackendTLSPolicy` on an HTTPRoute. Probes go by connection for the same reason,
and because Django answers a request whose `Host` is not in `ALLOWED_HOSTS` with
a 400 that would kill the pod forever.

`allowedHosts` defaults to `*` because Django refuses every request otherwise,
and a workload nobody can reach until a parameter is set is a workload nobody can
boot. Name the real hosts once the instance has an address.

## The Secret

`secretName` is read with `envFrom` and must hold `SECRET_KEY`,
`DATABASE_PASSWORD` and `DJANGO_SUPERUSER_PASSWORD`. All three have **published
defaults in the project's own compose file** — the key that signs sessions and
the password of the `admin` account included — so supplying them is not
hardening, it is the difference between an archive of your mail and everybody's.
kurly authors no Secret itself.

## The database

An external MySQL/MariaDB; the `mysql-cluster` workload provides one. Create the
database and the user before the first boot — the container migrates on start and
will not create either. `databaseType` moves it to PostgreSQL or to a SQLite file
on the volume.

## Less hardened, deliberately

One container runs several services: `s6-overlay` supervises the web server, a
RabbitMQ broker, the celery worker and beat, the database migrations and the
creation of the initial admin account, dropping privileges to their accounts as
it goes — which it can only do starting from root. gunicorn also binds `:443`.
The root filesystem is writable because RabbitMQ keeps its mnesia directory,
gunicorn its access log and Django its runtime files inside the image's own tree.

A first boot migrates the database and starts a broker before anything listens,
so the startup budget is generous (ten minutes) rather than the liveness delay
being stretched.

Four processes in one pod cost what four processes cost: a live boot settled just
under 2Gi, which is why the default limit is `3Gi` rather than something tidier.

## Persistence

The archive lives on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: eonvelope }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-eonvelope, namespace: eonvelope }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/eonvelope, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: eonvelope }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-eonvelope, namespace: eonvelope }
spec: { sourceRef: { kind: OCIRepository, name: kurly-eonvelope } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: eonvelope, namespace: eonvelope }
spec:
  serviceAccountName: eonvelope-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/eonvelope/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-eonvelope, importPath: github.com/metio/kurly/workloads/eonvelope }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: eonvelope, namespace: eonvelope }
spec:
  serviceAccountName: eonvelope-deployer
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
        name: eonvelope
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: eonvelope }
```

<!-- END generated: jaas-deploy -->
