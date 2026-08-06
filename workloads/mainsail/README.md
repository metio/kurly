<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mainsail

[Mainsail](https://github.com/mainsail-crew/mainsail) — the popular web interface for managing and controlling Klipper-based 3D printers. A **stateless** `kurly.http` workload on the official unprivileged image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mainsail = import 'github.com/metio/kurly/workloads/mainsail/server.libsonnet';
kurly.list(mainsail(moonrakerHost='printer.example.com'))
```

Serves on `:8080`.

Mainsail is a browser app: the printer's Moonraker API is called from the browser, not from
this pod, so `moonrakerHost` must be an address the browser can resolve. It writes the
`config.json` Mainsail reads on load, so nobody has to type the address in. Leave it out and
Mainsail asks for it in the browser instead — that stays the default, because where a printer
sits is not kurly's to assume. `config` overrides or extends the rest of that file verbatim.

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
metadata: { name: kurly, namespace: mainsail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mainsail, namespace: mainsail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mainsail, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mainsail }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mainsail, namespace: mainsail }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mainsail } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mainsail, namespace: mainsail }
spec:
  serviceAccountName: mainsail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mainsail/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mainsail, importPath: github.com/metio/kurly/workloads/mainsail }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mainsail, namespace: mainsail }
spec:
  serviceAccountName: mainsail-deployer
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
        name: mainsail
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mainsail }
```

<!-- END generated: jaas-deploy -->
