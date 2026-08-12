<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# collabora-online

[Collabora Online](https://www.collaboraonline.com/) — the editing engine behind
a self-hosted office suite: it renders and edits documents, spreadsheets and
presentations for a file application that embeds it over WOPI. A plain composable
`kurly.http` workload: documents live in the application it serves, not here.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local collabora = import 'github.com/metio/kurly/workloads/collabora-online/server.libsonnet';

kurly.list(collabora(
  wopiHosts=['nextcloud\\.example\\.com'],
  serverName='office.example.com',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `collabora-online` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | |
| `wopiHosts` | `[]` | hosts allowed to embed the editor, as regexes |
| `serverName` | none | the public URL it builds links against |
| `secretName` | none | admin console credentials |
| `sandbox` | `false` | chroot each document's process — needs `SYS_ADMIN` |
| `extraParams` | `[]` | further `coolwsd` settings |
| `resources` / `env` / `labels` / `annotations` | | |

Serves on `:9980` — compose an exposure onto it.

## It is half an application

Collabora Online edits documents somebody else stores: Nextcloud, ownCloud,
Seafile or anything speaking WOPI. On its own it serves an admin console and a
discovery endpoint and nothing a user wants. The file application is where a
deployment starts.

## The dots in `wopiHosts` matter

The entries become an allow-list of the hosts permitted to embed this editor,
**matched as regular expressions**. An unescaped dot matches any character, so
`files.example.com` also admits `filesXexample.com`. Escape them. An empty list
admits nobody, which is the safe default and not a working deployment.

## The sandbox is off by default

Collabora edits each document in a forked process, and can put that process in a
chroot of its own. Building that chroot is a mount-namespace operation needing
`CAP_SYS_ADMIN` — a capability close enough to root that granting it costs more
than the sandbox buys inside a container the kubelet already isolates. So
`security.capabilities` is disabled and no capability is added.

`sandbox=true` turns it back on for a deployment that wants defence in depth and
accepts a container holding `SYS_ADMIN` and `MKNOD`. The catalogue's security
score reflects the difference.

Memory scales with the number of documents open at once rather than with users, so
the default limit is a starting point for a small team. The sandbox roots and
caches are scratch volumes, so the root filesystem stays read-only.

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
metadata: { name: kurly, namespace: collabora-online }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-collabora-online, namespace: collabora-online }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/collabora-online, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: collabora-online }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-collabora-online, namespace: collabora-online }
spec: { sourceRef: { kind: OCIRepository, name: kurly-collabora-online } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: collabora-online, namespace: collabora-online }
spec:
  serviceAccountName: collabora-online-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/collabora-online/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-collabora-online, importPath: github.com/metio/kurly/workloads/collabora-online }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: collabora-online, namespace: collabora-online }
spec:
  serviceAccountName: collabora-online-deployer
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
        name: collabora-online
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: collabora-online }
```

<!-- END generated: jaas-deploy -->
