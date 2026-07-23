<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# passwordpusher

[Password Pusher](https://github.com/pglombardo/PasswordPusher) — share passwords
and secrets over self-destructing, expiring links. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pwpush = import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet';

kurly.list(pwpush())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `passwordpusher` | |
| `image` | `docker.io/pglombardo/pwpush:v2.9.3` | |
| `secretName` | `passwordpusher-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY_BASE` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:5100` — compose an exposure onto it:

```jsonnet
kurly.list([
  pwpush()
  + kurly.expose.ownGateway('pw.example.com', 'istio', tls='pwpush-tls'),
  kurly.certificate('pwpush-tls', ['pw.example.com'], 'letsencrypt-prod'),
])
```

## Database and secrets

Password Pusher reads `DATABASE_URL` and `SECRET_KEY_BASE` from the environment.
kurly authors **no Secret** — provide `passwordpusher-secrets` holding both keys
(the database password is embedded in `DATABASE_URL`), pulled in via `envFrom`. Fill
it with [`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `passwordpusher-db`. Being stateless (state
in the database), it can run several replicas.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: passwordpusher }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-passwordpusher, namespace: passwordpusher }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/passwordpusher, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: passwordpusher }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-passwordpusher, namespace: passwordpusher }
spec: { sourceRef: { kind: OCIRepository, name: kurly-passwordpusher } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: passwordpusher, namespace: passwordpusher }
spec:
  serviceAccountName: passwordpusher-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-passwordpusher, importPath: github.com/metio/kurly/workloads/passwordpusher }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: passwordpusher, namespace: passwordpusher }
spec:
  serviceAccountName: passwordpusher-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: passwordpusher
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: passwordpusher }
```

<!-- END generated: jaas-deploy -->
