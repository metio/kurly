<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# libretime

[LibreTime](https://github.com/libretime/libretime) — radio broadcast automation: a
programme calendar, a media library, and scheduled or live playout for a station. A
plain composable `kurly.http` workload on the project's `libretime-api` image; its
media library lives on a PersistentVolume and its PostgreSQL and RabbitMQ are
external.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local libretime = import 'github.com/metio/kurly/workloads/libretime/server.libsonnet';

kurly.list(
  libretime(
    publicUrl='https://radio.example.com',
    dbHost='libretime-db-rw',
    brokerHost='libretime-broker',
  )
  + kurly.expose.ingress('radio.example.com')
)
```

Every LibreTime component reads the same `/etc/libretime/config.yml`, and there is no
environment-variable form of it, so `config` is LibreTime's own schema rendered to
that file verbatim — kurly does not model it. The default document is built from the
parameters beside it (public URL, API key, Django secret key, database, broker). It
carries the database and broker passwords, so a real deployment sets `secretName`
instead: a consumer-provided Secret holding a complete `config.yml`, mounted over the
ConfigMap. kurly mints no Secret.

A full station also runs playout, liquidsoap, analyzer, a worker and the legacy PHP
interface, each its own image sharing this media volume. This stage carries the API —
the piece the others talk to — serving on `:9001`. The media library at
`/srv/libretime` is a ReadWriteOnce volume, so **one replica, recreated**.

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
metadata: { name: kurly, namespace: libretime }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-libretime, namespace: libretime }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/libretime, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: libretime }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-libretime, namespace: libretime }
spec: { sourceRef: { kind: OCIRepository, name: kurly-libretime } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: libretime, namespace: libretime }
spec:
  serviceAccountName: libretime-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/libretime/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-libretime, importPath: github.com/metio/kurly/workloads/libretime }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: libretime, namespace: libretime }
spec:
  serviceAccountName: libretime-deployer
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
        name: libretime
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: libretime }
```

<!-- END generated: jaas-deploy -->
