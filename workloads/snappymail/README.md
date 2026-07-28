<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# snappymail

[SnappyMail](https://snappymail.eu) — a fast, modern, self-hosted webmail client that connects to your existing IMAP/SMTP servers. A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); config and per-account data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local snappymail = import 'github.com/metio/kurly/workloads/snappymail/server.libsonnet';
kurly.list(snappymail())
```

SnappyMail is a client — configure your IMAP/SMTP servers in the admin panel. Data at `/var/lib/snappymail` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8888`.

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
metadata: { name: kurly, namespace: snappymail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-snappymail, namespace: snappymail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/snappymail, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: snappymail }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-snappymail, namespace: snappymail }
spec: { sourceRef: { kind: OCIRepository, name: kurly-snappymail } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: snappymail, namespace: snappymail }
spec:
  serviceAccountName: snappymail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/snappymail/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-snappymail, importPath: github.com/metio/kurly/workloads/snappymail }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: snappymail, namespace: snappymail }
spec:
  serviceAccountName: snappymail-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: snappymail
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: snappymail }
```

<!-- END generated: jaas-deploy -->
