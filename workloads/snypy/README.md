<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# snypy

[SnyPy](https://github.com/snypy) — stores and shares code snippets across a
team, with labels, revisions and per-team sharing. A plain composable
`kurly.http` workload on the official backend image, backed by an external
PostgreSQL.

This is the **API half**. SnyPy ships its web interface as a separate image
(`ghcr.io/snypy/snypy-ui`) that calls this one **from the browser**, which is why
the URLs below are the ones a user's browser resolves rather than in-cluster
addresses.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local snypy = import 'github.com/metio/kurly/workloads/snypy/server.libsonnet';

kurly.list(snypy(frontendUrl='https://snippets.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `snypy` | |
| `image` | `ghcr.io/snypy/snypy-backend:1.5.2` | |
| `frontendUrl` | `http://localhost:4200` | upstream's own placeholder — set it |
| `allowedHosts` | `['*']` | the `Host` headers Django accepts |
| `corsOrigins` / `csrfTrustedOrigins` | `[frontendUrl]` | browser origins allowed to call the API |
| `secretName` | `snypy` | `DATABASE_URL` and `SECRET_KEY` |
| `replicas` | `1` | all state is in PostgreSQL |
| `workers` | `2` | gunicorn processes, each a full copy of Django |

## Supply the Secret

kurly authors none. Two keys, both of which upstream publishes an example value
for — `SECRET_KEY` is literally `changeme!` in the project's compose file, and it
signs sessions as well as the registration and password-reset tokens.

```shell
kubectl create secret generic snypy \
  --from-literal=DATABASE_URL='postgresql://snypy:…@snypy-db-rw:5432/snypy' \
  --from-literal=SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

The defaults pair with a `cnpg-cluster` named `snypy-db`. The database password
is embedded in `DATABASE_URL`; nothing else needs it.

## The frontend URL is not decoration

Verification and password-reset mails carry links built from `frontendUrl`, so a
wrong value sends a new user to a page that is not there — and the account stays
unverified. It is also the origin CORS and CSRF are keyed on, so the web
interface cannot talk to the API until it matches.

## Probing

Every route is authenticated and there is no route at `/`, so any path a probe
could name answers 401, 404 or a redirect. The probes ask for a **connection**
instead. Django migrates the database and collects its static assets before
gunicorn binds, so first start gets a startup probe rather than a stretched
liveness delay.

## Ephemeral by design

Snippets live in PostgreSQL, so this stage claims no volume: point
`DATABASE_URL` at a database that is backed up and the pod holds nothing worth
keeping. The collected static assets are rewritten from the image on every start
and sit on a scratch volume.

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
metadata: { name: kurly, namespace: snypy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-snypy, namespace: snypy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/snypy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: snypy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-snypy, namespace: snypy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-snypy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: snypy, namespace: snypy }
spec:
  serviceAccountName: snypy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/snypy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-snypy, importPath: github.com/metio/kurly/workloads/snypy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: snypy, namespace: snypy }
spec:
  serviceAccountName: snypy-deployer
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
        name: snypy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: snypy }
```

<!-- END generated: jaas-deploy -->
