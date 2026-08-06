<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# librebooking

[LibreBooking](https://librebooking.readthedocs.io/) — resource and room
scheduling: who booked which room, meeting space or piece of equipment, and when.
A plain composable `kurly.http` workload on the project's
[own image](https://github.com/librebooking/docker), backed by an external
MySQL/MariaDB, with the generated configuration and the uploaded images and
attachments on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local librebooking = import 'github.com/metio/kurly/workloads/librebooking/server.libsonnet';

kurly.list(librebooking(scriptUrl='https://booking.example.com/Web'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `librebooking` | |
| `image` | `docker.io/librebooking/librebooking:5.3.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration (`/config`) |
| `uploadsSize` | `5Gi` | images and attachments (`/var/www/html/Web/uploads`) |
| `dbHost` / `database` / `dbUser` | `librebooking-db` / `librebooking` / `librebooking` | the MySQL/MariaDB |
| `scriptUrl` | unset | the absolute URL of the `Web` directory |
| `timezone` / `logLevel` | `UTC` / `none` | |
| `secretName` | `librebooking` | Secret with `LB_DATABASE_PASSWORD` and `LB_INSTALL_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:8080` — compose an exposure onto it.

## Database, secrets and the installer

LibreBooking needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. The coordinates come from env; `LB_DATABASE_PASSWORD` and
`LB_INSTALL_PASSWORD` come from a provided Secret via `envFrom`. kurly authors
**no Secret**.

The schema is created by LibreBooking's **own installer**, reached at
`/Web/install/` and guarded by `LB_INSTALL_PASSWORD` — so a fresh deployment is
not finished when the pod reports Ready, and the database user needs the rights to
create the schema until it is. `scriptUrl` has no sane default: every link and
every e-mail LibreBooking sends is built against it, so a wrong value survives
until somebody clicks a mail.

Background jobs (reminders, auto-release, waitlists) are the same image run as
`supercronic /config/lb-jobs-cron`; deploy them separately with `kurly.worker` if
you want them.

## Security and persistence

Apache is configured to listen on **8080** and the image already runs as
**www-data**, so the hardened posture stands apart from the root filesystem: the
entrypoint generates `config.php`, links it and each plugin's configuration back
into the install tree, restores `.htaccess` and writes a PHP timezone ini, all
inside the image's own tree, so the workload is composed with a writable root
filesystem. Configuration and uploads live on ReadWriteOnce volumes, so this is
**one replica, recreated**.

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
metadata: { name: kurly, namespace: librebooking }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-librebooking, namespace: librebooking }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/librebooking, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: librebooking }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-librebooking, namespace: librebooking }
spec: { sourceRef: { kind: OCIRepository, name: kurly-librebooking } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: librebooking, namespace: librebooking }
spec:
  serviceAccountName: librebooking-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/librebooking/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-librebooking, importPath: github.com/metio/kurly/workloads/librebooking }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: librebooking, namespace: librebooking }
spec:
  serviceAccountName: librebooking-deployer
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
        name: librebooking
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: librebooking }
```

<!-- END generated: jaas-deploy -->
