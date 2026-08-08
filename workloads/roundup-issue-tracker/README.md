<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# roundup-issue-tracker

[Roundup](https://www.roundup-tracker.org/) — an issue tracker reachable over the
web, by email and from a command line, on a schema the tracker owner edits. A
plain composable `kurly.http` workload; the tracker home — `config.ini`, the page
templates and the SQLite database — lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local roundup = import 'github.com/metio/kurly/workloads/roundup-issue-tracker/server.libsonnet';

kurly.list(roundup(webUrl='https://issues.example.com/issues/'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `roundup-issue-tracker` | |
| `image` | `rounduptracker/roundup:2.6.0-1` | |
| `tracker` | `issues` | served at `/<tracker>/` |
| `template` | `classic` | `classic`, `devel`, `jinja2`, `minimal`, `responsive` |
| `backend` | `sqlite` | `anydbm` or `sqlite` — see below |
| `webUrl` | `http://localhost:8080/issues/` | first run only |
| `secretName` | `roundup-issue-tracker` | holds `ADMIN_PASSWORD` |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/usr/src/app/tracker` |
| `env` / `resources` / `labels` / `annotations` | | |

## The first run is an interview, so an init container answers it

The image's start script installs a tracker by **asking** which template and which
backend on a terminal. No cluster provides one, so with nothing to answer it the
container exits and the pod never serves.

The init container runs the same two steps non-interactively — `roundup-admin
install` with the template, the backend and the web URL, then `roundup-admin
initialise` with the administrator's password — and the start script then finds a
configured tracker and execs the server. It only ever acts on what is missing, so
a tracker an operator has since edited, or that is full of issues, is left alone
on every restart.

`secretName` names the Secret holding `ADMIN_PASSWORD`, the password of the
tracker's `admin` account. It is read **once**, when the database is initialised;
changing it afterwards changes nothing, and `roundup-admin` on the volume is where
you set a new one.

## `webUrl` is written into everything the tracker sends

Roundup puts it into every link it renders and every mail it sends, so a wrong
value produces a site that works until somebody follows a link. It is read on the
**first run only** — afterwards it lives in `config.ini` on the volume, which is
where to change it.

## Backends

`sqlite` and `anydbm` are the two self-contained ones and are all this workload
supports in practice. Roundup also speaks PostgreSQL and MySQL, but those want a
server and a database URL in `config.ini` that nothing here supplies — point
`backend` at one only if you are prepared to write that configuration onto the
volume yourself.

## Persistence

One tracker home on a ReadWriteOnce volume, so **one replica, recreated** (never
rolled). The image already runs as its own unprivileged account; the uid is pinned
here only so the freshly provisioned volume is group-owned by it, without which the
install cannot write a single file.

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
metadata: { name: kurly, namespace: roundup-issue-tracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-roundup-issue-tracker, namespace: roundup-issue-tracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/roundup-issue-tracker, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: roundup-issue-tracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-roundup-issue-tracker, namespace: roundup-issue-tracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly-roundup-issue-tracker } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: roundup-issue-tracker, namespace: roundup-issue-tracker }
spec:
  serviceAccountName: roundup-issue-tracker-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/roundup-issue-tracker/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-roundup-issue-tracker, importPath: github.com/metio/kurly/workloads/roundup-issue-tracker }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: roundup-issue-tracker, namespace: roundup-issue-tracker }
spec:
  serviceAccountName: roundup-issue-tracker-deployer
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
        name: roundup-issue-tracker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: roundup-issue-tracker }
```

<!-- END generated: jaas-deploy -->
