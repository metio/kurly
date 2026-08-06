<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# domoticz

[Domoticz](https://www.domoticz.com/) — a home-automation system that monitors and configures switches, sensors, meters and weather devices, with its own event engine and dashboard. A `kurly.http` workload on the official image; database, scripts and plugins on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local domoticz = import 'github.com/metio/kurly/workloads/domoticz/server.libsonnet';
kurly.list(domoticz())
```

The entrypoint runs as root: it rsyncs the bundled examples onto the volume, chowns the userdata tree and marks the container configured beside the application, so the workload relaxes the non-root and read-only-rootfs defaults and grants back `CHOWN` and `FOWNER` only. Local-network discovery and USB radios do not work through a ClusterIP; devices reachable by IP or MQTT do. Userdata at `/opt/domoticz/userdata` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

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
metadata: { name: kurly, namespace: domoticz }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-domoticz, namespace: domoticz }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/domoticz, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: domoticz }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-domoticz, namespace: domoticz }
spec: { sourceRef: { kind: OCIRepository, name: kurly-domoticz } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: domoticz, namespace: domoticz }
spec:
  serviceAccountName: domoticz-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/domoticz/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-domoticz, importPath: github.com/metio/kurly/workloads/domoticz }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: domoticz, namespace: domoticz }
spec:
  serviceAccountName: domoticz-deployer
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
        name: domoticz
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: domoticz }
```

<!-- END generated: jaas-deploy -->
