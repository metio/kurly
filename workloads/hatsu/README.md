<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hatsu

[Hatsu](https://github.com/importantimport/hatsu) — a bridge that speaks
ActivityPub on behalf of a static site: it turns the site's JSON feed into a
Fediverse actor, accepts follows, pushes new posts to the followers and collects
the replies. A plain composable `kurly.http` workload keeping its SQLite database
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hatsu = import 'github.com/metio/kurly/workloads/hatsu/server.libsonnet';

kurly.list(hatsu(domain='hatsu.example.com', primaryAccount='blog.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `hatsu` | |
| `image` | the pinned `ghcr.io/importantimport/hatsu` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/data` |
| `domain` | unset | the domain in every `@handle` this instance mints |
| `primaryAccount` | unset | the static site being bridged, as a bare host |
| `secretName` | `hatsu` | holds `HATSU_ACCESS_TOKEN` |
| `logLevel` | `info` | `HATSU_LOG`, in `RUST_LOG` syntax |
| `env` / `resources` / `labels` / `annotations` | | |

## domain and primaryAccount are required

Hatsu panics on a missing `HATSU_DOMAIN` or `HATSU_PRIMARY_ACCOUNT` rather than
choosing something. Neither has a sane default — the domain becomes part of every
handle the instance mints, and the primary account is the site being bridged — so
both are unset here, and a pod that gets neither crash-loops by design.

## It fetches the site on first start

Creating the primary account reads that site's JSON feed over the internet, and a
failure there ends the process. The pod therefore needs egress, and the site needs
a feed Hatsu can parse, before the first roll ever succeeds. A NetworkPolicy that
forgets this egress keeps the workload from **starting**, not merely from
federating — which is why the startup probe here is generous: migrations and that
fetch both happen before anything listens.

## The admin API is off without a token

`HATSU_ACCESS_TOKEN` from `secretName` is what makes the admin API exist at all,
and creating any account beyond the primary one goes through it:

```shell
kubectl exec deploy/hatsu -- \
  curl -X POST "http://localhost:3939/api/v0/admin/create-account?name=blog.example.com&token=$HATSU_ACCESS_TOKEN"
```

kurly authors no Secret — mint one holding `HATSU_ACCESS_TOKEN` before the first
roll.

## Persistence

The SQLite database lives at `/data/hatsu.sqlite3`. `HATSU_DATABASE_URL` names it
absolutely and carries `?mode=rwc` deliberately: without that, SQLite opens an
existing file only and fails on an empty volume — exactly the state a fresh
deployment is in. Point it at an external PostgreSQL instead by setting
`HATSU_DATABASE_URL` through `env`.

One writer on a ReadWriteOnce volume, so **one replica, recreated** (never
rolled).

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
metadata: { name: kurly, namespace: hatsu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hatsu, namespace: hatsu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hatsu, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hatsu }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hatsu, namespace: hatsu }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hatsu } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hatsu, namespace: hatsu }
spec:
  serviceAccountName: hatsu-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hatsu/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hatsu, importPath: github.com/metio/kurly/workloads/hatsu }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hatsu, namespace: hatsu }
spec:
  serviceAccountName: hatsu-deployer
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
        name: hatsu
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hatsu }
```

<!-- END generated: jaas-deploy -->
