<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# piler

[piler](https://github.com/jsuto/piler/) — an email archive: every message a mail
system handles, kept deduplicated and encrypted for as long as a retention policy
says, searchable full text and exportable for an audit. A composable `kurly.http`
workload backed by an external MySQL/MariaDB, an external memcached and an
external Manticore Search, with the archive and the configuration directory each
on their own PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local piler = import 'github.com/metio/kurly/workloads/piler/server.libsonnet';

kurly.list(piler(hostname='archive.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `piler` | |
| `image` | `docker.io/sutoj/piler:1.4.9` | |
| `hostname` | `piler.example.com` | nginx `server_name`, the `hostid` in `piler.conf` and the base of every link the web interface builds — set it |
| `storageSize` / `storageClass` | `50Gi` / cluster default | `/var/piler/store`, the archived messages |
| `configSize` | `1Gi` | `/etc/piler`, generated on first start |
| `dbHost` / `database` / `dbUser` | `piler-db` / `piler` / `piler` | an external MySQL or MariaDB |
| `memcachedHost` | `memcached` | required, not optional — see below |
| `manticoreHost` | `manticore` | the full-text index, on `:9306` and `:9307` |
| `realtimeIndex` | `false` | `true` writes into a Manticore RT index as mail arrives instead of letting piler's cron index periodically |
| `secretName` | `piler` | `MYSQL_PASSWORD` |

## Two volumes, and the second one is not a convenience

`/etc/piler` is generated on first start from the templates the image carries:
`piler.conf`, the nginx site, `config-site.php`, a self-signed certificate — and
`piler.key`, the 56 bytes every archived message is encrypted with. An archive
whose configuration volume was thrown away is an archive nothing can read. Back
it up together with the store, never instead of it.

The database schema is created on first start too, into an empty database that
must already exist and be reachable with the credentials below.

## Three things it does not carry

| what | why it is external |
|---|---|
| MySQL / MariaDB | metadata, users, retention and audit policies |
| memcached | the entrypoint writes `MEMCACHED_ENABLED = 1` into `config-site.php` unconditionally, so there is nothing to turn off |
| Manticore Search | the full-text index, reached on `:9306` and `:9307` |

The Manticore server must be started against **piler's own** `manticore.conf` —
the file this workload's configuration volume holds — because the index
definitions are piler's, not Manticore's defaults. The `manticore` workload in
this repository runs the engine; pointing it at that configuration is a
deployment decision and is not wired up here.

## Supply the Secret

| key | what it is |
|---|---|
| `MYSQL_PASSWORD` | the database login, also written into `config-site.php` and `~/.my.cnf` on first start |

`ADMIN_USER_PASSWORD_HASH` may go in the same Secret. It resets the built-in
administrator's password on **every** start, and it is a hash rather than the
password, so nothing can generate it for you — mint it the way piler documents
and treat it as the way in, not as a rotation mechanism.

## Ports

`:80` is the web interface — compose an exposure onto it. `:25` is SMTP, which is
where mail actually arrives; it is not HTTP, so no Ingress or HTTPRoute can carry
it and the mail system in front has to reach the Service port directly.

## Single writer

The archive and the configuration are ReadWriteOnce volumes and the archiver
writes both, so this is one replica, recreated rather than rolled.

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
metadata: { name: kurly, namespace: piler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-piler, namespace: piler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/piler, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: piler }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-piler, namespace: piler }
spec: { sourceRef: { kind: OCIRepository, name: kurly-piler } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: piler, namespace: piler }
spec:
  serviceAccountName: piler-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/piler/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-piler, importPath: github.com/metio/kurly/workloads/piler }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: piler, namespace: piler }
spec:
  serviceAccountName: piler-deployer
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
        name: piler
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: piler }
```

<!-- END generated: jaas-deploy -->
