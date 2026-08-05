<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# evcc

[evcc](https://github.com/evcc-io/evcc) — a solar-aware charging controller for electric
vehicles: it reads your inverter, meters and wallboxes, and shifts charging into the hours
your own production covers. A plain composable `kurly.http` workload on the official
image, with its SQLite database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local evcc = import 'github.com/metio/kurly/workloads/evcc/server.libsonnet';

kurly.list(evcc(config={
  site: { title: 'Home', meters: { grid: 'grid', pv: ['pv'] } },
  meters: [
    { name: 'grid', type: 'template', template: 'demo-meter', power: -2500 },
    { name: 'pv', type: 'template', template: 'demo-meter', power: 4000 },
  ],
}))
```

`config` is evcc's own schema (site, meters, chargers, vehicles, loadpoints, tariffs),
mounted verbatim as `/etc/evcc.yaml` — kurly does not model it. It is `null` by default:
with no config file evcc boots into its configuration UI and stores what you enter in the
database. The database is pinned onto the volume with `EVCC_DATABASE_DSN`, so it survives
a restart instead of landing in the container's HOME.

The hardware evcc talks to lives on the LAN. Devices addressed by IP work as they are, but
the discovery protocols (mDNS, SMA Speedwire, KEBA, EEBus) are broadcast UDP that a pod
network does not carry — compose host networking if you need them.

Database at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the
web UI and API on `:7070`.

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
metadata: { name: kurly, namespace: evcc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-evcc, namespace: evcc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/evcc, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: evcc }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-evcc, namespace: evcc }
spec: { sourceRef: { kind: OCIRepository, name: kurly-evcc } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: evcc, namespace: evcc }
spec:
  serviceAccountName: evcc-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/evcc/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-evcc, importPath: github.com/metio/kurly/workloads/evcc }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: evcc, namespace: evcc }
spec:
  serviceAccountName: evcc-deployer
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
        name: evcc
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: evcc }
```

<!-- END generated: jaas-deploy -->
