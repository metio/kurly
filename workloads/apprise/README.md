<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apprise

[Apprise](https://github.com/caronc/apprise) — a self-hosted push-notification relay that fans one request out to 100+ services (email, Slack, Telegram, ntfy, webhooks, and more). A `kurly.http` workload on the official image; persistent named notification configs on a PersistentVolume under `/config`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local apprise = import 'github.com/metio/kurly/workloads/apprise/server.libsonnet';
kurly.list(apprise())
```

Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the API on `:8000`. It can also run stateless (POST with inline URLs) — drop the store if you never persist named configs.

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
metadata: { name: kurly, namespace: apprise }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-apprise, namespace: apprise }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/apprise, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: apprise }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-apprise, namespace: apprise }
spec: { sourceRef: { kind: OCIRepository, name: kurly-apprise } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: apprise, namespace: apprise }
spec:
  serviceAccountName: apprise-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/apprise/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-apprise, importPath: github.com/metio/kurly/workloads/apprise }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: apprise, namespace: apprise }
spec:
  serviceAccountName: apprise-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: apprise
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: apprise }
```

<!-- END generated: jaas-deploy -->
