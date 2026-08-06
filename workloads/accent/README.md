<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# accent

[Accent](https://github.com/mirego/accent) — a translation and localisation tool
for developers: it reads the translation files out of a repository, gives
translators a web app to work in, and writes the files back. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local accent = import 'github.com/metio/kurly/workloads/accent/server.libsonnet';

kurly.list(accent())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `accent` | |
| `image` | `docker.io/mirego/accent:v1.30.4` | |
| `secretName` | `accent` | Secret with `DATABASE_URL` and `SECRET_KEY_BASE` (envFrom) |
| `canonicalUrl` | | the URL the browser reaches this instance at |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:4000` — compose an exposure onto it:

```jsonnet
kurly.list([
  accent(canonicalUrl='https://accent.example.com')
  + kurly.expose.ownGateway('accent.example.com', 'istio', tls='accent-tls'),
  kurly.certificate('accent-tls', ['accent.example.com'], 'letsencrypt-prod'),
])
```

## Database and secrets

Accent reads `DATABASE_URL` and `SECRET_KEY_BASE` from the environment. kurly
authors **no Secret** — provide `accent` holding both keys (the database password
is embedded in `DATABASE_URL`), pulled in via `envFrom`. Fill it with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `accent-db`. `SECRET_KEY_BASE` signs the
session cookie, so a value that changes on every restart signs everybody out.

All state lives in PostgreSQL, so this stage claims no volume and can run several
replicas. The release migrates the database as it starts, which is why the first
boot against a fresh database is slower than the ones after it.

## Signing in

Accent authenticates through an external provider — GitHub, GitLab, Google, Slack
or Discord, each configured by its own environment variables — or with
`DUMMY_LOGIN_ENABLED=true`, which accepts an email address and no password. With
neither set nobody can sign in, so pick one before exposing it, and keep the dummy
login off anything reachable from outside the cluster.

`canonicalUrl` is the address the browser uses. Accent builds the links in its web
app and its emails from it, so leaving it unset renders a UI whose links point
somewhere else; there is no default that is right anywhere.

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
metadata: { name: kurly, namespace: accent }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-accent, namespace: accent }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/accent, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: accent }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-accent, namespace: accent }
spec: { sourceRef: { kind: OCIRepository, name: kurly-accent } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: accent, namespace: accent }
spec:
  serviceAccountName: accent-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/accent/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-accent, importPath: github.com/metio/kurly/workloads/accent }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: accent, namespace: accent }
spec:
  serviceAccountName: accent-deployer
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
        name: accent
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: accent }
```

<!-- END generated: jaas-deploy -->
