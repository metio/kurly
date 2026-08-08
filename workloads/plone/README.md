<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# plone

[Plone](https://plone.org/) — a content management system with workflow,
versioning and per-object permissions. This is the backend image: it serves the
managed content and the REST API the [Volto](https://github.com/plone/volto)
frontend talks to. A plain composable `kurly.http` workload; the object database
(`Data.fs`, its blobs and the template cache) lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local plone = import 'github.com/metio/kurly/workloads/plone/server.libsonnet';

kurly.list(plone())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `plone` | |
| `image` | `plone/plone-backend:6.2.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data` |
| `site` | `Plone` | the site id created in the Zope root; `null` creates none |
| `distribution` | `volto` | or `classic` for server-rendered pages |
| `adminSecretName` | | a Secret with an `inituser` key |
| `env` / `resources` / `labels` / `annotations` | | |

## The image ships admin/admin

Zope creates its first Manager account from `/app/inituser`, and the published
image carries one naming `admin` with the password `admin`. It is created the
first time the empty database starts, and the account then lives **in the
database** — editing the file afterwards no longer reaches it.

`adminSecretName` mounts a Secret over that file, which is the only moment the
credential can still be chosen. The key is `inituser` and its value is
`<user>:<password>`:

```shell
kubectl create secret generic plone --from-literal=inituser="admin:$(openssl rand -base64 24)"
```

Left unset, the instance comes up with the published credential, and changing it
from the Zope control panel immediately is on you.

## Creating the site

An empty Zope root answers requests and contains no CMS. `site` creates one on
start-up and is what makes the instance usable; creation is skipped when a site
of that id already exists, so it survives every restart. Upstream's own banner
calls the mechanism unfit for production — that is a statement about creating a
site while the server boots, not about the site it creates. Leaving `site` as
`null` and running the image's `create-site` command once is the deliberate
alternative.

`distribution` picks what is created: `volto` (headless, for the Volto frontend)
or `classic` (server-rendered pages).

## Writable root filesystem, deliberately

The entrypoint rewrites the instance's own configuration at every start — it
appends `etc/zope.conf.d` snippets to `etc/zope.conf`, seds the listen port into
`etc/zope.ini` and regenerates the CORS settings — all beside the code in
`/app`. Everything else stays at the hardened default: the image's own `plone`
account (uid/gid 500) runs it, no capabilities, no privilege escalation.

## Persistence

A FileStorage `Data.fs` on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). Two Zope processes writing one `Data.fs` corrupt it;
scaling out is what ZEO and RelStorage are for, and neither is this workload.

A first start compiles the translation catalogs and creates the site and its
default content before it binds anything, which takes minutes — hence the
startup probe rather than a stretched liveness delay.

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
metadata: { name: kurly, namespace: plone }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-plone, namespace: plone }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/plone, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: plone }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-plone, namespace: plone }
spec: { sourceRef: { kind: OCIRepository, name: kurly-plone } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: plone, namespace: plone }
spec:
  serviceAccountName: plone-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/plone/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-plone, importPath: github.com/metio/kurly/workloads/plone }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: plone, namespace: plone }
spec:
  serviceAccountName: plone-deployer
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
        name: plone
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: plone }
```

<!-- END generated: jaas-deploy -->
