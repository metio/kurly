<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apache-solr

[Apache Solr](https://github.com/apache/solr) — the search platform built on
Lucene: full-text indexing, faceting, filtering and highlighting over an
HTTP/JSON API. A plain composable `kurly.http` workload on the official image;
cores and indexes live on a PersistentVolume and it needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local solr = import 'github.com/metio/kurly/workloads/apache-solr/server.libsonnet';

kurly.list(solr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `apache-solr` | |
| `image` | `solr:9` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | cores, indexes and logs (`/var/solr`) |
| `env` / `resources` / `labels` / `annotations` | | give the JVM headroom for large indexes |

Serves the API and the admin UI on **:8983**.

## A warning about exposing it

**Solr has no authentication until a `security.json` is put in place.** It
answers whoever reaches it, and that includes the admin UI, which can create and
drop collections and edit configuration. An exposure on its own publishes an
unauthenticated index with an administrative interface attached. Keep it inside
the cluster and reach it from your own application, or put something in front
that authenticates.

## SOLR_PORT is a listen port, not a URL

A Service named after this workload makes Kubernetes inject `SOLR_PORT` as
`tcp://10.x.x.x:8983` — and `bin/solr` reads `SOLR_PORT` as the port to *listen*
on. The injected URL is parsed as a port number and the server never comes up.
`kurly.disableServiceLinks` is composed in for exactly that reason; nothing here
needs the links.

## Running unprivileged

The image builds a `solr` account (uid 8983) and its entrypoint chowns `/var/solr`
only when it starts as root. Naming that account skips the chown, so the
**restricted** posture holds and `fsGroup` makes the volume writable instead —
the same shape [manticore](../manticore/) and [couchdb](../couchdb/) have.

`/tmp` is ephemeral scratch: the JVM unpacks and writes temporary files there,
and nothing in it is worth keeping.

## Starting up

A cold JVM plus core discovery takes well past a liveness probe's patience, and
the admin API answers 404 until Solr has finished loading — so the wait is a
**startup probe**, not a longer liveness delay.

## Persistence, and the topology this is not

One index directory on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two Solr processes off the same files. This is
the standalone server. SolrCloud — sharding and replication coordinated through
ZooKeeper — is a different topology and is not what this stage renders.

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
metadata: { name: kurly, namespace: apache-solr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-apache-solr, namespace: apache-solr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/apache-solr, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: apache-solr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-apache-solr, namespace: apache-solr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-apache-solr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: apache-solr, namespace: apache-solr }
spec:
  serviceAccountName: apache-solr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/apache-solr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-apache-solr, importPath: github.com/metio/kurly/workloads/apache-solr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: apache-solr, namespace: apache-solr }
spec:
  serviceAccountName: apache-solr-deployer
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
        name: apache-solr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: apache-solr }
```

<!-- END generated: jaas-deploy -->
