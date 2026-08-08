<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sosse

[Sosse](https://gitlab.com/biolds1/sosse) — Selenium Open Source Search Engine.
It crawls sites with a headless browser, keeps its own copies of the pages as
screenshots and HTML snapshots, and searches that archive offline. A composable
`kurly.http` workload backed by an external PostgreSQL, with the archive on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sosse = import 'github.com/metio/kurly/workloads/sosse/server.libsonnet';

kurly.list(sosse())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sosse` | |
| `image` | `biolds/sosse:latest` | see the note on pinning |
| `storageSize` / `storageClass` | `20Gi` / cluster default | the archive (`/var/lib/sosse`) |
| `dbHost` / `dbPort` / `database` / `dbUser` | `sosse-db-rw` … | pairs with a `cnpg-cluster` named `sosse-db` |
| `secretName` | `sosse` | holds `SOSSE_DB_PASS` |
| `env` / `resources` / `labels` / `annotations` | | a real browser, so give it memory |

Serves the web UI and the search API on `:80` — compose an exposure onto it:

```jsonnet
kurly.list([
  sosse()
  + kurly.expose.ownGateway('search.example.com', 'istio', tls='sosse-tls'),
  kurly.certificate('sosse-tls', ['search.example.com'], 'letsencrypt-prod'),
])
```

## The bundled PostgreSQL is not used

The image ships a PostgreSQL server and its default command starts it, so the
container runs happily on a laptop with no database anywhere. That is exactly
what makes it wrong here: the data would live in the image's own
`/var/lib/postgresql`, a major-version upgrade would run inside the container,
and nothing in a cluster could back it up or fail it over.

The command is therefore overridden to `/run.sh`, the entrypoint one layer down,
which waits for `SOSSE_DB_HOST` to answer, migrates, and starts uwsgi, nginx and
the crawler. Point `dbHost` at a PostgreSQL that is backed up — a `cnpg-cluster`
named `sosse-db` lines up with the defaults.

The command also writes a sudoers drop-in first, and that is not cosmetic.
`/run.sh` runs one of its start-up steps as `sudo -u www-data`, and sudo resets
the environment — so that one step loses `SOSSE_DB_*` and falls back to the
configuration file's `127.0.0.1`, where nothing listens once the bundled server
is skipped. It fails with a Django traceback while every other step succeeds and
the pod still goes Ready, so nothing but the logs shows it: the MIME handlers
the crawler dispatches on are simply never loaded. The drop-in keeps those five
variables across sudo.

## Supply the Secret — the default password is published

Sosse's own `db_pass` default is the literal `sosse`, and the entrypoint writes
it into the configuration file it generates on first start. Every `sosse.conf`
option can also be set as `SOSSE_<option>` in the environment, and the
environment wins over the file, which is how one key in a Secret replaces it:

```shell
kubectl create secret generic sosse \
  --from-literal=SOSSE_DB_PASS="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

The same mechanism sets anything else — `SOSSE_PROXY`,
`SOSSE_CHROMIUM_OPTIONS`, `SOSSE_SCREENSHOTS_DIR` — through `env`, which is
merged over the defaults so a key set there wins.

The first account is `admin` / `admin`. Change it before exposing anything.

## Service links are switched off

Sosse reads **every** `SOSSE_`-prefixed environment variable as a configuration
option. A Service named `sosse` makes Kubernetes inject `SOSSE_PORT`,
`SOSSE_SERVICE_HOST` and friends, which would land in its configuration as
nonsense — so this workload disables service links.

## Less hardened, deliberately

The entrypoint runs as root: it writes `/etc/sosse/sosse.conf`, creates and
chowns `/run/sosse`, `/var/log/sosse` and the data directory, then drops to
`www-data` for the crawler and for uwsgi's workers. nginx binds `:80` from its
root master process. The root filesystem is writable because the configuration,
the logs, the uwsgi socket and nginx's temporary bodies are all written inside
the image's own tree. The crawler drives a real headless browser, so `/dev/shm`
gets an emptyDir — the default 64MiB is not enough for it.

## Persistence

Screenshots, HTML snapshots, collected static files and crawler scripts live on
a ReadWriteOnce volume, and one crawler runs beside the web server in the same
container, so this is **one replica, recreated** (never rolled). The index
itself is in PostgreSQL.

## Pinning

`server.image` pins `tag@sha256:…`. The tag says which version, the digest says
which bits; Renovate watches that file.

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
metadata: { name: kurly, namespace: sosse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sosse, namespace: sosse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sosse, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sosse }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sosse, namespace: sosse }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sosse } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sosse, namespace: sosse }
spec:
  serviceAccountName: sosse-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sosse/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sosse, importPath: github.com/metio/kurly/workloads/sosse }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sosse, namespace: sosse }
spec:
  serviceAccountName: sosse-deployer
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
        name: sosse
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sosse }
```

<!-- END generated: jaas-deploy -->
