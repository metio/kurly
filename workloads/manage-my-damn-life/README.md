<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# manage-my-damn-life

[Manage My Damn Life](https://github.com/intri-in/manage-my-damn-life-nextjs) — a
web front end for the CalDAV servers you already run: tasks and calendars from
several accounts in one place, with labels, filters and reminders. A composable
`kurly.http` workload backed by an external database and nothing else — it keeps
no files of its own, so it claims no volume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mmdl = import 'github.com/metio/kurly/workloads/manage-my-damn-life/server.libsonnet';

kurly.list(mmdl(baseUrl='https://tasks.example.com/'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `manage-my-damn-life` | |
| `image` | `docker.io/intriin/mmdl:v0.9.3` | |
| `dbDialect` | `postgres` | also `mysql` or `sqlite` |
| `dbHost` / `dbPort` / `dbName` / `dbUser` | `manage-my-damn-life-db-rw` … | pairs with a `cnpg-cluster` named `manage-my-damn-life-db` |
| `baseUrl` | absent | the URL people visit |
| `secretName` | `manage-my-damn-life` | two credentials, see below |

## The first visit installs it

The image starts the Next.js server directly and migrates nothing on boot. A
fresh database is an application that answers on `:3000` and has no tables until
somebody walks `/install` once, which is what creates the schema and the first
account. That is why the probes test the connection rather than a path: every
path redirects to `/install` or to the login page depending on how far setup has
got, and a probe following one would kill the pod exactly while somebody is
installing it.

## Supply the Secret

```shell
kubectl create secret generic manage-my-damn-life \
  --from-literal=DB_PASS=… \
  --from-literal=AES_PASSWORD="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

`AES_PASSWORD` encrypts the CalDAV passwords the application stores on a user's
behalf. Changing it later does not re-encrypt them — it makes every stored
account unreadable, and each user has to enter their password again.

Third-party sign-in (`USE_NEXT_AUTH=true` with Keycloak, Authentik or Google) is
off by default; switching it on through `env` means adding `NEXTAUTH_SECRET` and
the provider's client credentials to the same Secret.

## Persistence

None of its own. Everything durable is in the database, so point `dbHost` at one
that is backed up — and set `baseUrl` to the URL a browser reaches this instance
at, since that is what absolute links and NextAuth callbacks are built from.

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
metadata: { name: kurly, namespace: manage-my-damn-life }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-manage-my-damn-life, namespace: manage-my-damn-life }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/manage-my-damn-life, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: manage-my-damn-life }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-manage-my-damn-life, namespace: manage-my-damn-life }
spec: { sourceRef: { kind: OCIRepository, name: kurly-manage-my-damn-life } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: manage-my-damn-life, namespace: manage-my-damn-life }
spec:
  serviceAccountName: manage-my-damn-life-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/manage-my-damn-life/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-manage-my-damn-life, importPath: github.com/metio/kurly/workloads/manage-my-damn-life }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: manage-my-damn-life, namespace: manage-my-damn-life }
spec:
  serviceAccountName: manage-my-damn-life-deployer
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
        name: manage-my-damn-life
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: manage-my-damn-life }
```

<!-- END generated: jaas-deploy -->
