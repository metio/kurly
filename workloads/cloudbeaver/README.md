<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cloudbeaver

[CloudBeaver](https://github.com/dbeaver/cloudbeaver) Community — the browser
database console from the DBeaver project. Connect to PostgreSQL, MySQL, SQLite
and the rest, browse schemas, and run SQL without installing a desktop client. A
plain composable `kurly.http` workload whose entire workspace — configuration,
saved connections, users and query history — lives on a PersistentVolume.

It is a console **for** databases, not a database. The servers it connects to are
configured by an administrator at runtime and are not dependencies of this
workload: nothing needs to exist for it to start.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cloudbeaver = import 'github.com/metio/kurly/workloads/cloudbeaver/server.libsonnet';

kurly.list(cloudbeaver())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cloudbeaver` | |
| `image` | `dbeaver/cloudbeaver:26.1.4` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the workspace (`/opt/cloudbeaver/workspace`) |
| `env` | `{}` | extra settings; see the warning about `JAVA_OPTS` below |
| `resources` / `labels` / `annotations` | | JVM, so the memory limit matters |

Serves the console on `:8978` — compose an exposure onto it:

```jsonnet
kurly.list([
  cloudbeaver()
  + kurly.expose.ownGateway('db.example.com', 'istio', tls='cloudbeaver-tls'),
  kurly.certificate('cloudbeaver-tls', ['db.example.com'], 'letsencrypt-prod'),
])
```

The first visit walks through creating the administrator account. Put an
authenticating proxy in front of it if the console is reachable from anywhere
untrusted — it holds credentials for every database it can reach.

## `JAVA_OPTS` is load-bearing

CloudBeaver is an Eclipse application, and Equinox insists on writing its bundle
cache and a lock file into the configuration area that ships **inside the image**,
beside the code. On a read-only root filesystem it does not start at all:

```text
java.io.IOException: Unable to create lock manager
```

So this workload sets `JAVA_OPTS` to move the writable half onto the volume and
name the shipped one as the shared, read-only half — Eclipse's own
cascaded-configuration arrangement for a read-only install:

```text
-Dosgi.configuration.area=/opt/cloudbeaver/workspace/.osgi
-Dosgi.sharedConfiguration.area=/opt/cloudbeaver/server/configuration
```

**Passing your own `JAVA_OPTS` through `env` replaces this and the server will not
start.** Append to it rather than setting it fresh. The alternative would have
been `kurly.writableRootFilesystem`, handing over the whole install tree to get
one cache directory.

## Running unprivileged

The image builds a `dbeaver` user at uid/gid 8978 and then never selects it, so it
runs as root by default. Its entrypoint chowns the workspace and drops privileges
with `su` when started as root — but takes a different path when it is already
non-root and runs the server directly. Naming the account the image itself
provisioned takes that path, and keeps the **restricted** posture: no root, no
privilege escalation, no capabilities, read-only root filesystem.

## It restarts once on a fresh volume

Expect exactly one restart the first time a new volume comes up: the container
exits with 143 about two and a half minutes in, having logged a clean startup and
no error, and the replacement runs indefinitely. Booting a new pod against an
already-initialised volume restarts zero times, which is what pins the trigger to
first-run workspace setup rather than to anything in this configuration.

It is recorded here because a single unexplained restart in `kubectl get pods` is
otherwise the sort of thing that sends somebody hunting through probe timings for
a fault that is not there.

## Persistence

One workspace on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the files — the same single-writer discipline
as [adminer](../adminer/) has no need for, because unlike a stateless console this
one remembers its connections and users.

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
metadata: { name: kurly, namespace: cloudbeaver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cloudbeaver, namespace: cloudbeaver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cloudbeaver, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cloudbeaver }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cloudbeaver, namespace: cloudbeaver }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cloudbeaver } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cloudbeaver, namespace: cloudbeaver }
spec:
  serviceAccountName: cloudbeaver-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/cloudbeaver/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cloudbeaver, importPath: github.com/metio/kurly/workloads/cloudbeaver }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cloudbeaver, namespace: cloudbeaver }
spec:
  serviceAccountName: cloudbeaver-deployer
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
        name: cloudbeaver
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cloudbeaver }
```

<!-- END generated: jaas-deploy -->
