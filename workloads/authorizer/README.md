<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# authorizer

[Authorizer](https://authorizer.dev) — an authentication server: sign-up and
sign-in, social logins, multi-factor, and the OAuth2/OIDC endpoints applications
point at. A plain composable `kurly.http` workload: every account and session
lives in the external database, so it claims no volume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local authorizer = import 'github.com/metio/kurly/workloads/authorizer/server.libsonnet';

kurly.list(authorizer(
  secretName='authorizer',
  appUrl='https://auth.example.com',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `authorizer` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | every replica must carry the same `JWT_SECRET` |
| `databaseType` | `postgres` | or `mysql`, `sqlite`, `mongodb`, … |
| `appUrl` | none | the URL a browser reaches this at |
| `secretName` | `authorizer` | see below |
| `jwtType` | `HS256` | |
| `extraArgs` | `[]` | appended to the command line verbatim |
| `resources` / `labels` / `annotations` | | |

Serves the API, the login pages and the admin dashboard on `:8080` — compose an
exposure onto it.

## Secrets reach it through a shell, deliberately

Authorizer v2 takes **all** of its configuration as command-line flags and reads
no environment variables at all — in its own words, "The server does not read from
`.env` or OS environment variables." Writing the admin secret and the JWT secret
straight into `args` would put both in the Deployment spec, readable by anything
that can read Deployments. So the container runs `sh -c` and expands them from the
Secret at startup, which is the pattern upstream documents for the same reason:

```shell
kubectl create secret generic authorizer \
  --from-literal=DATABASE_URL='postgres://…' \
  --from-literal=ADMIN_SECRET="$(openssl rand -base64 24)" \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=CLIENT_ID="$(openssl rand -hex 16)" \
  --from-literal=CLIENT_SECRET="$(openssl rand -hex 32)"
```

The values are still visible in the process's own argv inside this container; what
this buys is keeping them out of the manifest and out of the API server.

Replicas scale, but every one of them must carry the same `JWT_SECRET`, or a
token minted by one is rejected by the next.

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
metadata: { name: kurly, namespace: authorizer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-authorizer, namespace: authorizer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/authorizer, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: authorizer }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-authorizer, namespace: authorizer }
spec: { sourceRef: { kind: OCIRepository, name: kurly-authorizer } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: authorizer, namespace: authorizer }
spec:
  serviceAccountName: authorizer-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/authorizer/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-authorizer, importPath: github.com/metio/kurly/workloads/authorizer }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: authorizer, namespace: authorizer }
spec:
  serviceAccountName: authorizer-deployer
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
        name: authorizer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: authorizer }
```

<!-- END generated: jaas-deploy -->
