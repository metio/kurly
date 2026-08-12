<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pydio-cells

[Pydio Cells](https://pydio.com) — a file sharing and collaboration platform:
workspaces, sharing links, versioning and an activity feed over storage you own.
A plain composable `kurly.http` workload: the files and Cells' own configuration
live under `CELLS_WORKING_DIR` on a PersistentVolume, with the metadata in an
external MySQL/MariaDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cells = import 'github.com/metio/kurly/workloads/pydio-cells/server.libsonnet';

kurly.list(cells(externalUrl='https://files.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pydio-cells` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | the working directory (`/var/cells`) |
| `externalUrl` | none | what Cells puts in share links |
| `env` | `{}` | any other `CELLS_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## It configures itself on first start, through a wizard

The image's entrypoint checks whether Cells is installed and, if not, turns
`cells start` into `cells configure`. So the first request lands on a setup form
that asks for the database and the first administrator, and the probes here are by
connection rather than a path that does not answer yet. Nothing is stored until
somebody completes it.

## TLS terminates in front of it

Cells enables TLS on its own site by default and then wants a certificate before
it will answer. `CELLS_SITE_NO_TLS` is set so the exposure in front holds the
certificate instead, which is the arrangement a cluster deployment wants.

`externalUrl` is what Cells puts in share links and OAuth redirects. Left unset it
uses whatever it can infer, and the links it hands out resolve only from inside
the cluster.

Single writer: one working directory on a ReadWriteOnce volume, so one replica,
recreated.

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
metadata: { name: kurly, namespace: pydio-cells }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pydio-cells, namespace: pydio-cells }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pydio-cells, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pydio-cells }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pydio-cells, namespace: pydio-cells }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pydio-cells } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pydio-cells, namespace: pydio-cells }
spec:
  serviceAccountName: pydio-cells-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pydio-cells/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pydio-cells, importPath: github.com/metio/kurly/workloads/pydio-cells }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pydio-cells, namespace: pydio-cells }
spec:
  serviceAccountName: pydio-cells-deployer
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
        name: pydio-cells
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pydio-cells }
```

<!-- END generated: jaas-deploy -->
