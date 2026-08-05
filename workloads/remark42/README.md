<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# remark42

[Remark42](https://github.com/umputun/remark42) — a lightweight comment engine for
static sites and blogs. Drop a script tag on a page and readers can comment,
signing in with a social provider or anonymously, without handing them to a
third-party service. A plain composable `kurly.http` workload: comments live in an
embedded BoltDB on a PersistentVolume, so it needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local remark42 = import 'github.com/metio/kurly/workloads/remark42/server.libsonnet';

kurly.list(remark42(siteUrl='https://comments.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `remark42` | |
| `image` | `umputun/remark42:v1.9.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/srv/var` |
| `siteUrl` | **required** | where remark42 itself is served |
| `site` | `remark` | the SITE id the widget asks for |
| `secretName` | `remark42` | supplies `SECRET` |
| `env` | `{}` | `REMARK_*` settings, including auth providers |
| `resources` / `labels` / `annotations` | | |

```jsonnet
kurly.list([
  remark42(siteUrl='https://comments.example.com')
  + kurly.expose.ownGateway('comments.example.com', 'istio', tls='remark42-tls'),
  kurly.certificate('remark42-tls', ['comments.example.com'], 'letsencrypt-prod'),
])
```

## `siteUrl` has no sensible default

It is baked into the widget script readers load and into every OAuth callback, so
a wrong value gives you comments that load nowhere and logins that return to the
wrong host — both of which look like the site is broken rather than misconfigured.

## The Secret

`SECRET` signs the JWTs readers hold, and remark42 **refuses to start without
it** — which is the right behaviour, and the reason kurly mints none.

```shell
kubectl create secret generic remark42 \
  --from-literal=SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## No login providers are configured by default

The log says so plainly on start:

```text
[WARN] no auth providers defined
```

Readers can still comment anonymously if you enable it; add GitHub, Google, and
the rest through `env` (`REMARK_AUTH_GITHUB_CID` and friends). This workload
configures none, because which identity provider a site trusts is not something
kurly can pick.

## Persistence

One BoltDB file on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled). BoltDB takes a single writer lock, so a second pod would not
corrupt the file — it simply never opens it.

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
metadata: { name: kurly, namespace: remark42 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-remark42, namespace: remark42 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/remark42, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: remark42 }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-remark42, namespace: remark42 }
spec: { sourceRef: { kind: OCIRepository, name: kurly-remark42 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: remark42, namespace: remark42 }
spec:
  serviceAccountName: remark42-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/remark42/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-remark42, importPath: github.com/metio/kurly/workloads/remark42 }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: remark42, namespace: remark42 }
spec:
  serviceAccountName: remark42-deployer
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
        name: remark42
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: remark42 }
```

<!-- END generated: jaas-deploy -->
