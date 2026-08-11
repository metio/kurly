<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# olivetin

[OliveTin](https://olivetin.app) — a web interface that turns a handful of shell
commands into buttons, for the people who should be allowed to run them and
nothing else. A plain composable `kurly.http` workload: its whole state is
`config.yaml`, rendered as a ConfigMap, so it needs no database and no
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local olivetin = import 'github.com/metio/kurly/workloads/olivetin/server.libsonnet';

kurly.list(olivetin(actions=[
  { title: 'Check disk space', shell: 'df -h /', onclick: 'execution-dialog' },
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `olivetin` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | |
| `actions` | `[]` | OliveTin action definitions, verbatim |
| `logLevel` | `INFO` | |
| `config` | `{}` | merged over the rendered `config.yaml` |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and REST API on `:1337` — compose an exposure onto it.

## What the buttons can reach

Every action is a shell command run inside this container, so it can only use
what the image ships and can only touch what this pod can touch. That is the
security boundary worth thinking about before exposing it: anything the container
can do, a button can do. `actions` starts empty rather than carrying the upstream
demo set, which invites `cat ~/.bash_history` through a web page.

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
metadata: { name: kurly, namespace: olivetin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-olivetin, namespace: olivetin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/olivetin, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: olivetin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-olivetin, namespace: olivetin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-olivetin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: olivetin, namespace: olivetin }
spec:
  serviceAccountName: olivetin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/olivetin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-olivetin, importPath: github.com/metio/kurly/workloads/olivetin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: olivetin, namespace: olivetin }
spec:
  serviceAccountName: olivetin-deployer
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
        name: olivetin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: olivetin }
```

<!-- END generated: jaas-deploy -->
