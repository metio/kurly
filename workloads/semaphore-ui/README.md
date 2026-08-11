<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# semaphore-ui

[Semaphore UI](https://semaphoreui.com) — a web interface for running Ansible
playbooks, Terraform plans and shell scripts, with projects, schedules and an
audit trail. A plain composable `kurly.http` workload: the default database is
BoltDB in a file on a PersistentVolume, so a single instance needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local semaphore = import 'github.com/metio/kurly/workloads/semaphore-ui/server.libsonnet';

kurly.list(semaphore(secretName='semaphore'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `semaphore-ui` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the BoltDB file (`/var/lib/semaphore`) |
| `dbDialect` | `bolt` | or `postgres` / `mysql` |
| `dbHost` / `dbName` / `dbUser` | none / `semaphore` / `semaphore` | for an external database |
| `secretName` | none | see below |
| `adminName` / `adminEmail` | `admin` / `admin@example.com` | the first user |
| `publicUrl` | none | the URL Semaphore builds its links from |
| `env` | `{}` | any other `SEMAPHORE_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:3000` — compose an exposure onto it.

## Secrets

`secretName` is required in any real deployment:

```shell
kubectl create secret generic semaphore \
  --from-literal=SEMAPHORE_ACCESS_KEY_ENCRYPTION="$(head -c32 /dev/urandom | base64)" \
  --from-literal=SEMAPHORE_ADMIN_PASSWORD="$(openssl rand -base64 18)"
```

`SEMAPHORE_ACCESS_KEY_ENCRYPTION` is the key every SSH key and cloud credential
Semaphore stores is encrypted with. Changing it makes the stored keys unreadable,
so it belongs in a Secret from the first boot rather than being left to a default.

## What it runs

Playbooks execute as child processes in this container, against whatever the pod
can reach. The image ships Ansible; anything else a playbook calls has to be there
too.

Single writer: one BoltDB file on a ReadWriteOnce volume, so one replica,
recreated. Point `dbDialect`/`dbHost` at PostgreSQL or MySQL to run more than one.

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
metadata: { name: kurly, namespace: semaphore-ui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-semaphore-ui, namespace: semaphore-ui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/semaphore-ui, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: semaphore-ui }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-semaphore-ui, namespace: semaphore-ui }
spec: { sourceRef: { kind: OCIRepository, name: kurly-semaphore-ui } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: semaphore-ui, namespace: semaphore-ui }
spec:
  serviceAccountName: semaphore-ui-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/semaphore-ui/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-semaphore-ui, importPath: github.com/metio/kurly/workloads/semaphore-ui }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: semaphore-ui, namespace: semaphore-ui }
spec:
  serviceAccountName: semaphore-ui-deployer
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
        name: semaphore-ui
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: semaphore-ui }
```

<!-- END generated: jaas-deploy -->
