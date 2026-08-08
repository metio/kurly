<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# coder

[Coder](https://github.com/coder/coder) — provisions remote development
workspaces on your own infrastructure from Terraform templates, and hands
developers a browser IDE, SSH and port forwarding into them. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL
and keeping no state of its own.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local coder = import 'github.com/metio/kurly/workloads/coder/server.libsonnet';

kurly.list(coder(accessUrl='https://coder.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `coder` | |
| `image` | `ghcr.io/coder/coder:v2.36.0` | |
| `accessUrl` | unset | the address agents and browsers reach |
| `port` | `8080` | bound and published |
| `secretName` | `coder` | holds `CODER_PG_CONNECTION_URL` |
| `replicas` | `1` | |

## Supply the Secret

kurly authors none. One key, and the default pairs with a `cnpg-cluster` named
`coder-db`:

```shell
kubectl create secret generic coder \
  --from-literal=CODER_PG_CONNECTION_URL='postgres://coder:…@coder-db-rw:5432/coder?sslmode=disable'
```

## The access URL is not optional in practice

Workspace agents dial back in on `CODER_ACCESS_URL`, so it must be the address
they can reach — not the in-cluster Service name. Left unset the server still
starts and falls back to localhost, and every workspace it creates then comes up
and never connects. That failure looks like a broken template rather than a
missing setting, which is why it is worth setting before the first workspace.

## Provisioning is a separate decision

A template that creates Kubernetes workspaces needs RBAC over the namespace
those pods land in, and those permissions belong to the template rather than to
this server. Bind them yourself and point the app at that ServiceAccount with
`kurly.serviceAccount`, or run external provisioner daemons and leave this
deployment without cluster permissions at all.

## Scaling and state

Everything durable is in PostgreSQL; the provisioner cache is a scratch volume,
so there is no PersistentVolume here and nothing pins the pod to a node.
Coordinating more than one replica is a licensed feature upstream, which is why
the default is one — point the connection URL at a database that is backed up
and the server itself stays disposable.

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
metadata: { name: kurly, namespace: coder }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-coder, namespace: coder }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/coder, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: coder }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-coder, namespace: coder }
spec: { sourceRef: { kind: OCIRepository, name: kurly-coder } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: coder, namespace: coder }
spec:
  serviceAccountName: coder-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/coder/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-coder, importPath: github.com/metio/kurly/workloads/coder }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: coder, namespace: coder }
spec:
  serviceAccountName: coder-deployer
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
        name: coder
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: coder }
```

<!-- END generated: jaas-deploy -->
