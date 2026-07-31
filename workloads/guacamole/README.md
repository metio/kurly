<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# guacamole

[Apache Guacamole](https://guacamole.apache.org) — a clientless remote-desktop gateway: reach
RDP, VNC and SSH machines from a browser, no plugins. Guacamole is **two processes** — the web
app and the `guacd` proxy daemon — so this workload runs **guacd as a sidecar** in the same pod
(reached on `localhost:4822`), backed by an external PostgreSQL or MySQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local guacamole = import 'github.com/metio/kurly/workloads/guacamole/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='guacamole-db', database='guacamole'),
  guacamole(),
])
```

The web app's database connection (`POSTGRESQL_*` / `MYSQL_*`) comes from a Secret via `envFrom`
— kurly authors **no Secret** — and the database schema must be initialised (see the Guacamole
docs). Stateless (connections and users live in the database). Serves on `:8080` (Guacamole is
under `/guacamole`).

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
metadata: { name: kurly, namespace: guacamole }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-guacamole, namespace: guacamole }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/guacamole, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: guacamole }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-guacamole, namespace: guacamole }
spec: { sourceRef: { kind: OCIRepository, name: kurly-guacamole } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: guacamole, namespace: guacamole }
spec:
  serviceAccountName: guacamole-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/guacamole/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-guacamole, importPath: github.com/metio/kurly/workloads/guacamole }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: guacamole, namespace: guacamole }
spec:
  serviceAccountName: guacamole-deployer
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
        name: guacamole
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: guacamole }
```

<!-- END generated: jaas-deploy -->
