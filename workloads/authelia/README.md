<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# authelia

[Authelia](https://www.authelia.com) — a self-hosted authentication and authorization gateway that adds single sign-on and 2FA in front of your other apps, via a reverse proxy's forward-auth. A `kurly.http` workload on the official image; its `configuration.yml` mounted as a ConfigMap, with the default SQLite storage on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local authelia = import 'github.com/metio/kurly/workloads/authelia/server.libsonnet';
kurly.list(authelia(config={ /* your Authelia configuration.yml */ }))
```

`config` is Authelia's own `configuration.yml`, mounted verbatim — kurly does not model it. The default is a **minimal skeleton that must be completed** for your domain, identity backend and access rules. The session/storage/JWT secrets come from a Secret via `envFrom` (as `AUTHELIA_*` env) — kurly authors **no Secret**. Data at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:9091`.

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
metadata: { name: kurly, namespace: authelia }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-authelia, namespace: authelia }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/authelia, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: authelia }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-authelia, namespace: authelia }
spec: { sourceRef: { kind: OCIRepository, name: kurly-authelia } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: authelia, namespace: authelia }
spec:
  serviceAccountName: authelia-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/authelia/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-authelia, importPath: github.com/metio/kurly/workloads/authelia }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: authelia, namespace: authelia }
spec:
  serviceAccountName: authelia-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: authelia
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: authelia }
```

<!-- END generated: jaas-deploy -->
