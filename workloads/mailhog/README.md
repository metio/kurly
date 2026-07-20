<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mailhog

[MailHog](https://github.com/mailhog/MailHog) — a self-hosted email-testing tool for developers: it captures the mail your apps send and shows it in a web inbox instead of delivering it. A **stateless** `kurly.http` workload on the official image (pinned by digest — Renovate maintains it).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mailhog = import 'github.com/metio/kurly/workloads/mailhog/server.libsonnet';
kurly.list(mailhog())
```

Apps send mail to its SMTP listener on `:1025` (needs an extra Service). Serves the web inbox on `:8025`.

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
metadata: { name: kurly, namespace: mailhog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mailhog, namespace: mailhog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mailhog, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mailhog }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mailhog, namespace: mailhog }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mailhog } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mailhog, namespace: mailhog }
spec:
  serviceAccountName: mailhog-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mailhog/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mailhog, importPath: github.com/metio/kurly/workloads/mailhog }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mailhog, namespace: mailhog }
spec:
  serviceAccountName: mailhog-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mailhog
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mailhog }
```

<!-- END generated: jaas-deploy -->
