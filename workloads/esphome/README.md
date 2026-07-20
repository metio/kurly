<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# esphome

[ESPHome](https://esphome.io) — the web dashboard and compiler for creating and flashing firmware for ESP8266/ESP32 smart-home devices from YAML. A `kurly.http` workload on the official image; device configs and build artifacts on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local esphome = import 'github.com/metio/kurly/workloads/esphome/server.libsonnet';
kurly.list(esphome())
```

Runs as root to compile firmware; OTA flashing works over the network. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:6052`.

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
metadata: { name: kurly, namespace: esphome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-esphome, namespace: esphome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/esphome, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: esphome }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-esphome, namespace: esphome }
spec: { sourceRef: { kind: OCIRepository, name: kurly-esphome } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: esphome, namespace: esphome }
spec:
  serviceAccountName: esphome-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/esphome/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-esphome, importPath: github.com/metio/kurly/workloads/esphome }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: esphome, namespace: esphome }
spec:
  serviceAccountName: esphome-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: esphome
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: esphome }
```

<!-- END generated: jaas-deploy -->
