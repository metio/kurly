<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# zigbee2mqtt

[Zigbee2MQTT](https://www.zigbee2mqtt.io) — bridges a Zigbee network onto MQTT,
so Zigbee devices are usable by anything that speaks MQTT without the vendor's own
hub or cloud. A plain composable `kurly.http` workload: the device database and
settings live in files under `/app/data` on a PersistentVolume, and everything
else is published to the broker.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local zigbee2mqtt = import 'github.com/metio/kurly/workloads/zigbee2mqtt/server.libsonnet';

kurly.list(zigbee2mqtt(
  mqttServer='mqtt://mosquitto:1883',
  serialPort='tcp://zigbee-gw:6638',
  adapter='ember',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `zigbee2mqtt` | |
| `image` | the pinned upstream image | |
| `mqttServer` | `mqtt://mosquitto:1883` | the broker to publish to |
| `serialPort` | none | the Zigbee adapter |
| `adapter` | none | `ember`, `zstack`, `deconz`, `zigate` or `zboss` |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the device database (`/app/data`) |
| `env` | `{}` | any other `ZIGBEE2MQTT_CONFIG_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the frontend on `:8080` — compose an exposure onto it.

## The adapter is the whole question

Zigbee2MQTT talks to a Zigbee radio, and a pod cannot be handed a USB stick that
is plugged into some node — a workload that assumed one would run on exactly one
machine and be un-schedulable everywhere else. So `serialPort` defaults to nothing
and the arrangement that works in a cluster is a network coordinator: a
`tcp://host:port` adapter (a serial-over-IP bridge, an ethernet coordinator) that
any node can reach. A USB adapter is still possible by pinning the pod to its node
and adding the device, and that is a decision to make deliberately rather than a
default to inherit.

An MQTT broker is required — Zigbee2MQTT publishes everything it knows to the
broker and does nothing useful without one.

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
metadata: { name: kurly, namespace: zigbee2mqtt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-zigbee2mqtt, namespace: zigbee2mqtt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/zigbee2mqtt, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: zigbee2mqtt }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-zigbee2mqtt, namespace: zigbee2mqtt }
spec: { sourceRef: { kind: OCIRepository, name: kurly-zigbee2mqtt } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: zigbee2mqtt, namespace: zigbee2mqtt }
spec:
  serviceAccountName: zigbee2mqtt-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/zigbee2mqtt/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-zigbee2mqtt, importPath: github.com/metio/kurly/workloads/zigbee2mqtt }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: zigbee2mqtt, namespace: zigbee2mqtt }
spec:
  serviceAccountName: zigbee2mqtt-deployer
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
        name: zigbee2mqtt
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: zigbee2mqtt }
```

<!-- END generated: jaas-deploy -->
