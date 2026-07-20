<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mosquitto

[Eclipse Mosquitto](https://mosquitto.org) — a lightweight, self-hosted MQTT message broker, the backbone of most IoT and home-automation setups. Mosquitto speaks MQTT, not HTTP: it listens on `:1883`, with a `mosquitto.conf` mounted as a ConfigMap and its persistence database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mosquitto = import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet';
kurly.list(mosquitto())
```

`config` is Mosquitto's `mosquitto.conf`, mounted verbatim; the default allows anonymous clients — a real broker sets up authentication. WebSockets (`:9001`) need a listener in the config and a second Service. Data at `/mosquitto/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves MQTT on `:1883`.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: mosquitto }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mosquitto, namespace: mosquitto }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mosquitto, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mosquitto }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mosquitto, namespace: mosquitto }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mosquitto } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mosquitto, namespace: mosquitto }
spec:
  serviceAccountName: mosquitto-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mosquitto, importPath: github.com/metio/kurly/workloads/mosquitto }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mosquitto, namespace: mosquitto }
spec:
  serviceAccountName: mosquitto-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mosquitto
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mosquitto }
```

<!-- END generated: jaas-deploy -->
