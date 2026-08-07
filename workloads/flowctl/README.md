<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# flowctl

[flowctl](https://flowctl.net) — a self-service workflow execution platform:
flows defined in YAML, run on a schedule or on request, with approvals in front
of the steps that need one. A plain composable `kurly.http` workload on the
official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local flowctl = import 'github.com/metio/kurly/workloads/flowctl/server.libsonnet';

kurly.list(flowctl())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `flowctl` | |
| `image` | `ghcr.io/cvhariharan/flowctl:0.14.0` | |
| `flowsSize` / `flowsStorageClass` | `1Gi` / cluster default | `/app/flows` |
| `logsSize` / `logsStorageClass` | `2Gi` / cluster default | `/var/log/flowctl` |
| `dbHost` / `dbPort` / `dbName` / `dbUser` / `dbSslMode` | `flowctl-db-rw` / `5432` / `flowctl` / `flowctl` / `disable` | a [cnpg-cluster](../cnpg-cluster/) named `flowctl-db` |
| `adminUser` | `flowctl_admin` | the superadmin, fixed after the first install |
| `rootUrl` | `http://localhost:7000` | the URL a browser reaches this install at |
| `secretName` | `flowctl` | read with `envFrom` |
| `workers` / `flowExecutionTimeout` / `timezone` | `10` / `1h` / `UTC` | scheduler |
| `env` / `resources` / `labels` / `annotations` | | merged over the defaults |

Serves the interface, the API and `/metrics` on `:7000`. Compose an exposure onto
it, and set `rootUrl` to the host that exposure answers on — it is what the
interface builds its links and OIDC redirects against.

## Configuration is environment only

Without a `config.toml` beside the binary, flowctl builds its whole configuration
from `FLOWCTL_`-prefixed variables (`__` separates the sections) and then
validates it, so a required setting left out stops the process instead of falling
back to a default. That is why the stage writes the full block rather than the
interesting half of it; `env` merges over it, so a key you set wins.

## The Secret

kurly authors no Secret. Three keys, all required:

```shell
kubectl create secret generic flowctl \
  --from-literal=FLOWCTL_DB__PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=FLOWCTL_APP__ADMIN_PASSWORD="$(openssl rand -base64 18)" \
  --from-literal=KEYSTORE_KEY="$(openssl rand -base64 32 | tr '+/' '-_')"
```

`KEYSTORE_KEY` is the key flowctl encrypts stored credentials with. It is 32
bytes, base64url-encoded, and the entrypoint turns it into the
`base64key://<key>` URL the keystore wants — a Secret can carry the key material
but not a URL scheme. **Keep it**: with a different key the flow secrets already
in the database cannot be read back, and the empty `base64key://` that would
otherwise do (gocloud reads it as "generate a random key") loses them at every
restart without saying anything.

## Database

An external PostgreSQL, addressed by the discrete `dbHost`/`dbPort`/`dbName`/
`dbUser` settings — the `install` subcommand builds its own connection string
from those and ignores a DSN. The schema migration and the superadmin account run
as an init container before every start; it is idempotent, so a fresh database
comes up without a manual step.

## Persistence

Two ReadWriteOnce volumes: the flow definitions at `/app/flows`, and the
execution logs at `/var/log/flowctl` — a run's log is the record of what an
approval let happen, so nothing rotates or deletes them until an operator says
how long they are kept. Single writer, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: flowctl }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-flowctl, namespace: flowctl }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/flowctl, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: flowctl }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-flowctl, namespace: flowctl }
spec: { sourceRef: { kind: OCIRepository, name: kurly-flowctl } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: flowctl, namespace: flowctl }
spec:
  serviceAccountName: flowctl-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/flowctl/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-flowctl, importPath: github.com/metio/kurly/workloads/flowctl }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: flowctl, namespace: flowctl }
spec:
  serviceAccountName: flowctl-deployer
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
        name: flowctl
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: flowctl }
```

<!-- END generated: jaas-deploy -->
