<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lldap

[LLDAP](https://github.com/lldap/lldap) — a light LDAP implementation for authentication:
a simple, opinionated user/group directory with a friendly web UI, a lightweight stand-in
for OpenLDAP that apps authenticate against. A plain composable `kurly.http` workload on
the official image; with the default SQLite backend its directory lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lldap = import 'github.com/metio/kurly/workloads/lldap/server.libsonnet';
kurly.list(lldap())
```

Apps bind over LDAP on `:3890`, a separate port — add a Service for it (a raw `+` patch).
LLDAP needs `LLDAP_JWT_SECRET` and `LLDAP_LDAP_USER_PASS` (the admin password) from a
Secret via `envFrom` — kurly authors **no Secret**. Point it at an external
PostgreSQL/MySQL (`LLDAP_DATABASE_URL`) to scale past the single SQLite writer. Directory
at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on
`:17170`.

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
metadata: { name: kurly, namespace: lldap }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lldap, namespace: lldap }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lldap, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lldap }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lldap, namespace: lldap }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lldap } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lldap, namespace: lldap }
spec:
  serviceAccountName: lldap-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lldap/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lldap, importPath: github.com/metio/kurly/workloads/lldap }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lldap, namespace: lldap }
spec:
  serviceAccountName: lldap-deployer
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
        name: lldap
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lldap }
```

<!-- END generated: jaas-deploy -->
