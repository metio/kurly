<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pelican-panel

[Pelican Panel](https://pelican.dev/) — a web control panel for running and managing
game servers. A plain composable `kurly.http` workload on the official image that
keeps its SQLite database, its `.env`, uploads and plugins under `/pelican-data` on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pelican = import 'github.com/metio/kurly/workloads/pelican-panel/server.libsonnet';

kurly.list(pelican(appUrl='https://panel.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pelican-panel` | |
| `image` | `ghcr.io/pelican-dev/panel:v1.0.0-beta36` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the data volume (`/pelican-data`) |
| `appUrl` | none | the public URL the panel builds links and assets against |
| `behindProxy` | `true` | keep Caddy on plain `:80` and leave TLS to the proxy in front |
| `trustedProxies` | `*` | whose forwarded headers Caddy and Laravel trust |
| `secretName` | none | optional Secret with `APP_KEY` and any database credentials (`envFrom`) |
| `env` | `{}` | extra environment (`DB_CONNECTION`, `DB_HOST`, … for an external database) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:80` — compose an exposure onto it:

```jsonnet
kurly.list([
  pelican(appUrl='https://panel.example.com')
  + kurly.expose.ownGateway('panel.example.com', 'istio', tls='pelican-panel-tls'),
  kurly.certificate('pelican-panel-tls', ['panel.example.com'], 'letsencrypt-prod'),
])
```

The first visit runs the panel's own installer, which writes the admin account and
the finished configuration into `/pelican-data/.env`. Put an exposure in front of it
before you open it to anyone else.

## Behind a proxy

The entrypoint decides what Caddy listens on. With `behindProxy` (the default) it
listens on plain `:80` with automatic HTTPS off and takes the public origin from
`appUrl` — what an Ingress or HTTPRoute terminating TLS in front of it wants. Turning
it off makes Caddy bind the `appUrl` host itself and demand a Let's Encrypt address
for an `https://` URL.

## Database and secrets

SQLite on the volume by default. Point `DB_CONNECTION` / `DB_HOST` / `DB_PORT` /
`DB_DATABASE` / `DB_USERNAME` through `env` at an external MySQL or PostgreSQL (the
[mysql-cluster](../mysql-cluster/) or [cnpg-cluster](../cnpg-cluster/) workload) to
scale past the single SQLite writer, and pass the password through `secretName`.

The entrypoint mints an `APP_KEY` into `/pelican-data/.env` on first start when the
environment carries none, so a Secret is optional — kurly authors **no Secret**. Set
`APP_KEY` through a provided Secret to pin the key across a rebuilt volume; sessions
and encrypted values do not survive it changing.

## Security and persistence

The image runs as its own `www-data` user, and Caddy binds the privileged `:80`
through a file capability. This workload therefore grants `NET_BIND_SERVICE` back on
top of kurly's dropped-`ALL` default and allows privilege escalation — without it
`no_new_privs` discards the file capability and nothing ever listens. The root
filesystem is writable because the Laravel tree is optimized, cached and logged into
in place.

Migrations and the Filament optimize pass make the first start slow, so this workload
carries a **startup probe** rather than a lenient liveness probe. The SQLite database
and the uploads live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: pelican-panel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pelican-panel, namespace: pelican-panel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pelican-panel, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pelican-panel }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pelican-panel, namespace: pelican-panel }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pelican-panel } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pelican-panel, namespace: pelican-panel }
spec:
  serviceAccountName: pelican-panel-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pelican-panel/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pelican-panel, importPath: github.com/metio/kurly/workloads/pelican-panel }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pelican-panel, namespace: pelican-panel }
spec:
  serviceAccountName: pelican-panel-deployer
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
        name: pelican-panel
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pelican-panel }
```

<!-- END generated: jaas-deploy -->
