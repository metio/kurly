<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# 2fauth

[2FAuth](https://github.com/Bubka/2FAuth) — a self-hosted web app to manage your TOTP/HOTP two-factor-authentication accounts and generate one-time codes. A `kurly.http` workload on the official image; with the default SQLite backend its database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local twofauth = import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet';
kurly.list(twofauth(appUrl='https://2fa.example.com'))
```

`APP_KEY` (encrypts stored 2FA secrets) comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/2fauth` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8000`.

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
metadata: { name: kurly, namespace: 2fauth }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-2fauth, namespace: 2fauth }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/2fauth, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: 2fauth }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-2fauth, namespace: 2fauth }
spec: { sourceRef: { kind: OCIRepository, name: kurly-2fauth } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: 2fauth, namespace: 2fauth }
spec:
  serviceAccountName: 2fauth-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-2fauth, importPath: github.com/metio/kurly/workloads/2fauth }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: 2fauth, namespace: 2fauth }
spec:
  serviceAccountName: 2fauth-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: 2fauth
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: 2fauth }
```

<!-- END generated: jaas-deploy -->
