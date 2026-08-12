<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# onedev

[OneDev](https://onedev.io/) — a self-contained DevOps platform: Git hosting,
code search, pull requests, issues and a CI/CD engine in one server. A composable
`kurly.http` workload: repositories, attachments and — by default — the database
itself live under `/opt/onedev` on a PersistentVolume, so nothing else is needed
to run it.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local onedev = import 'github.com/metio/kurly/workloads/onedev/server.libsonnet';

kurly.list(onedev(storageSize='100Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `onedev` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | repositories and data (`/opt/onedev`) |
| `dbUrl` / `dbUser` | none | an external database (a JDBC URL) |
| `secretName` | none | `hibernate_connection_password` |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:6610` and Git-over-SSH on `:6611` — compose an
exposure onto the HTTP port, and route the SSH port separately if clones over SSH
are wanted.

## It installs itself into the volume, as root

The image's entrypoint copies and upgrades the application tree into
`/opt/onedev` on every start and then runs the Java service wrapper, which manages
its own child process. Both want to own that tree, so this stage relaxes two
defaults deliberately: it runs as root, and it allows the privilege escalation the
wrapper needs. The root filesystem stays read-only — everything written goes to
the volume or a scratch mount — and nothing else about the hardened posture is
given up.

## Builds run somewhere

The server can execute CI jobs in its own container, which means a job can do
whatever this pod can do. A OneDev used for CI should point at a Kubernetes
executor instead, so jobs run as their own pods with their own limits.

Single writer: the embedded database and the repositories are one directory on a
ReadWriteOnce volume, so one replica, recreated. `dbUrl` moves the metadata to an
external PostgreSQL, which is what a busy instance wants.

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
metadata: { name: kurly, namespace: onedev }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-onedev, namespace: onedev }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/onedev, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: onedev }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-onedev, namespace: onedev }
spec: { sourceRef: { kind: OCIRepository, name: kurly-onedev } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: onedev, namespace: onedev }
spec:
  serviceAccountName: onedev-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/onedev/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-onedev, importPath: github.com/metio/kurly/workloads/onedev }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: onedev, namespace: onedev }
spec:
  serviceAccountName: onedev-deployer
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
        name: onedev
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: onedev }
```

<!-- END generated: jaas-deploy -->
