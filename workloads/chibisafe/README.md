<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# chibisafe

[chibisafe](https://chibisafe.app/) — a file uploader with drag-and-drop, albums
and shareable links. It runs as **three stages**, which is what the application
really is: the `server` (the fastify backend, the SQLite database and the uploaded
files), the `frontend` (the Next.js application a browser renders) and the `proxy`
(the Caddy edge that joins the two into one origin and serves the uploads).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/chibisafe/server.libsonnet';
local frontend = import 'github.com/metio/kurly/workloads/chibisafe/frontend.libsonnet';
local proxy = import 'github.com/metio/kurly/workloads/chibisafe/proxy.libsonnet';

kurly.list([
  server(storageSize='200Gi'),
  frontend(),
  // The one stage that faces the browser.
  proxy() + kurly.expose.ingress('files.example.com'),
  // The Secret the server reads ADMIN_PASSWORD from.
  kurly.externalSecret('chibisafe', { name: 'vault', kind: 'ClusterSecretStore' }, [
    { secretKey: 'ADMIN_PASSWORD', remoteRef: { key: 'chibisafe/admin', property: 'password' } },
  ]),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `namePrefix` | `chibisafe` | every stage's name derives from it |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the uploads, at `/app/uploads` |
| `databaseSize` | `2Gi` | the SQLite database, at `/app/database` |
| `secretName` | `chibisafe` | holds `ADMIN_PASSWORD` |
| `apiUrl` (frontend) | the sibling server | in-cluster address, not the public one |

## Expose the proxy, and only the proxy

The frontend on its own is not a working install: `/api`, `/docs` and the uploaded
files all have to come from the same origin, and the backend answers 401 to
everything without a session or an API key. The proxy serves the whole application
on `:8080`.

It is not a convenience. **In a released image the backend serves no files at
all** — its static route is registered only outside production — so the links
chibisafe hands out are answered by this stage or by nothing. Upstream's compose
file puts Caddy in front for the same reason; the Caddyfile here is that one,
restated over the stage names (upstream's are the literal hosts `chibisafe` and
`chibisafe_server`, which no namespace can run two copies of).

## Storage: two volumes, two pods

The server owns both, because they grow at completely different rates:

| path | holds |
| --- | --- |
| `/app/uploads` | the uploaded files, their thumbnails and the generated zips |
| `/app/database` | the SQLite database — users, albums, tags, links |

The proxy mounts the uploads claim **read-only**. With the `ReadWriteOnce` default
that keeps the two pods on the same node; pass a ReadWriteMany `storageClass` (and
`accessModes`) to the server to spread them.

The server is **one replica, recreated** — one SQLite database, one writer. The
frontend and the proxy hold nothing and scale horizontally.

## Less hardened, deliberately

The server's start script runs `prisma migrate deploy && prisma generate` before
anything listens, and `generate` writes the client into `/app/node_modules`, inside
the image's own tree and owned by root. That stage therefore runs as root with a
writable root filesystem; an ordinary uid exits before the port is ever bound. The
frontend and the proxy keep the hardened default.

## The first account

The backend creates an `admin` user on first start with the password from
`ADMIN_PASSWORD` in the Secret. Change it from the application once you are in —
the environment variable is read on every start, but the account is only created
once, so afterwards the two say different things.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: chibisafe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-chibisafe, namespace: chibisafe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/chibisafe, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: chibisafe }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-chibisafe, namespace: chibisafe }
spec: { sourceRef: { kind: OCIRepository, name: kurly-chibisafe } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chibisafe-frontend, namespace: chibisafe }
spec:
  serviceAccountName: chibisafe-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local frontend = import 'github.com/metio/kurly/workloads/chibisafe/frontend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(frontend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chibisafe, importPath: github.com/metio/kurly/workloads/chibisafe }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chibisafe-proxy, namespace: chibisafe }
spec:
  serviceAccountName: chibisafe-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local proxy = import 'github.com/metio/kurly/workloads/chibisafe/proxy.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(proxy())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chibisafe, importPath: github.com/metio/kurly/workloads/chibisafe }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chibisafe-server, namespace: chibisafe }
spec:
  serviceAccountName: chibisafe-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/chibisafe/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chibisafe, importPath: github.com/metio/kurly/workloads/chibisafe }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: chibisafe, namespace: chibisafe }
spec:
  serviceAccountName: chibisafe-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: frontend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: chibisafe-frontend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chibisafe-frontend }
    - name: proxy
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: chibisafe-proxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chibisafe-proxy }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: chibisafe-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chibisafe-server }
```

<!-- END generated: jaas-deploy -->
