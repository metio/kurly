<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jupyterlab

[JupyterLab](https://github.com/jupyterlab/jupyterlab) — the web-based
interactive development environment for notebooks, code and data — on the Jupyter
project's own `base-notebook` image. A plain composable `kurly.http` workload; the
workspace under `/home/jovyan/work` lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jupyterlab = import 'github.com/metio/kurly/workloads/jupyterlab/server.libsonnet';

kurly.list(jupyterlab())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `jupyterlab` | |
| `image` | `quay.io/jupyter/base-notebook` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/home/jovyan/work` |
| `secretName` | `jupyterlab` | holds `JUPYTER_TOKEN`, read with `envFrom` |
| `env` / `resources` / `labels` / `annotations` | | |

## The token is a root password

The server authenticates with a token. Without `JUPYTER_TOKEN` it mints a random
one at boot and prints it to the log, which nobody reaches through an Ingress —
so the token comes from a Secret you provide. kurly authors none.

Anyone holding it **runs arbitrary code** in this pod, as this pod's
ServiceAccount, on this pod's volume: a notebook server is a shell with a web
interface. Put it behind TLS, and behind an authenticating proxy if the instance
is reachable from the internet.

## Probes

Every HTTP path either redirects to `/lab` or answers 403 without the token, so
the probes check the connection instead. A first start unpacks the lab assets and
builds the kernel spec, which is what the startup probe's budget covers.

## Persistence

Only `/home/jovyan/work` is on the volume — the environment itself is the image,
so a package installed from a notebook is gone at the next restart. Bake what you
need into your own image, or install it into the workspace from a notebook that
lives there.

One workspace on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled).

## Less hardened, deliberately

The root filesystem is writable: the server keeps its runtime state, kernel
connection files, settings and caches inside its own home directory, which is part
of the image tree.

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
metadata: { name: kurly, namespace: jupyterlab }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jupyterlab, namespace: jupyterlab }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jupyterlab, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jupyterlab }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jupyterlab, namespace: jupyterlab }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jupyterlab } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jupyterlab, namespace: jupyterlab }
spec:
  serviceAccountName: jupyterlab-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jupyterlab/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jupyterlab, importPath: github.com/metio/kurly/workloads/jupyterlab }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jupyterlab, namespace: jupyterlab }
spec:
  serviceAccountName: jupyterlab-deployer
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
        name: jupyterlab
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jupyterlab }
```

<!-- END generated: jaas-deploy -->
