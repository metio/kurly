<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ezbookkeeping

[ezBookkeeping](https://github.com/mayswind/ezbookkeeping) — a lightweight
personal finance and accounting app: accounts, transactions, categories and
reports, with a mobile-friendly UI. A plain composable `kurly.http` workload whose
SQLite database lives on a PersistentVolume, so it needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ezbookkeeping = import 'github.com/metio/kurly/workloads/ezbookkeeping/server.libsonnet';

kurly.list(ezbookkeeping())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ezbookkeeping` | |
| `image` | `mayswind/ezbookkeeping:1.6.1` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/ezbookkeeping/data` |
| `secretName` | `ezbookkeeping` | supplies `EBK_SECURITY_SECRET_KEY` |
| `env` | `{}` | any `EBK_*` setting, including `EBK_DATABASE_*` |
| `resources` / `labels` / `annotations` | | |

Serves on `:8080`:

```jsonnet
kurly.list([
  ezbookkeeping()
  + kurly.expose.ownGateway('money.example.com', 'istio', tls='ezbookkeeping-tls'),
  kurly.certificate('ezbookkeeping-tls', ['money.example.com'], 'letsencrypt-prod'),
])
```

## Supply the secret key — the default is published

`EBK_SECURITY_SECRET_KEY` signs the tokens users hold. The image ships a default,
and that default is in a public repository: an instance running with it will accept
session tokens **anybody can mint**. This is not a hardening nicety, it is the
difference between an account and none.

```shell
kubectl create secret generic ezbookkeeping \
  --from-literal=EBK_SECURITY_SECRET_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

Changing it later invalidates every issued token, logging everybody out — which is
the correct response to suspecting it leaked.

## Probes

It publishes no health endpoint: `/healthz`, `/health` and the usual variants all
answer 404. The probes therefore request the app itself, which returns 200 without
authentication.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the file. The log and attachment
directories are ephemeral scratch — neither is worth a volume — and pointing
`EBK_DATABASE_*` at MySQL or PostgreSQL moves the database off it entirely.

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
metadata: { name: kurly, namespace: ezbookkeeping }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ezbookkeeping, namespace: ezbookkeeping }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ezbookkeeping, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ezbookkeeping }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ezbookkeeping, namespace: ezbookkeeping }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ezbookkeeping } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ezbookkeeping, namespace: ezbookkeeping }
spec:
  serviceAccountName: ezbookkeeping-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ezbookkeeping/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ezbookkeeping, importPath: github.com/metio/kurly/workloads/ezbookkeeping }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ezbookkeeping, namespace: ezbookkeeping }
spec:
  serviceAccountName: ezbookkeeping-deployer
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
        name: ezbookkeeping
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ezbookkeeping }
```

<!-- END generated: jaas-deploy -->
