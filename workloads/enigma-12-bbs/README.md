<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# enigma-12-bbs

[ENiGMA½](https://github.com/NuSkooler/enigma-bbs) — a modern bulletin board
system engine: message bases, file areas, ANSI art and legacy door games, spoken
over telnet. A composable `kurly.http` workload on the project's own image, with
its configuration, databases and file base each on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local enigma = import 'github.com/metio/kurly/workloads/enigma-12-bbs/server.libsonnet';

kurly.list(enigma())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `enigma-12-bbs` | |
| `image` | `enigmabbs/enigma-bbs` | |
| `boardName` | `ENiGMA BBS` | written once, at first boot |
| `configSize` | `1Gi` | `/enigma-bbs/config` |
| `databaseSize` | `5Gi` | `/enigma-bbs/db` |
| `fileBaseSize` | `10Gi` | `/enigma-bbs/filebase` |
| `storageClass` / `env` / `resources` / `labels` / `annotations` | | |

## Telnet, not HTTP

Callers arrive on **:8888 over telnet**, a raw TCP protocol, so the HTTP
exposure recipes have nothing to route: reach the board with a `LoadBalancer` or
`NodePort` Service, or a Gateway API `TCPRoute`. Telnet carries the login in
clear text — the engine also speaks SSH, which needs a key pair on the config
volume and the listener enabled in `config.hjson`.

## First boot writes the configuration

The image's entrypoint builds a configuration by asking questions on a terminal.
A cluster provides none, so nothing answers and the container exits. This
workload does that setup itself, in an init container: it copies the engine's own
menu templates onto the volume, splices the include list the way the project's
generator does, and writes a `config.hjson` carrying the board name and one
message conference. Everything else stays at the engine's defaults.

It writes only what is missing, so edits made afterwards — a second message area,
an SSH listener, the web content server — survive every restart. The container
then runs `main.js` directly.

## Less hardened, deliberately

The image declares no user and the engine creates directories inside its own
install tree before it listens, so this runs as **root on a writable root
filesystem**. Nothing beyond that is relaxed: capabilities stay dropped and
privilege escalation stays off, because :8888 is unprivileged and nothing drops
privileges.

## Persistence

Three ReadWriteOnce volumes — configuration and menus, the SQLite databases
holding users and message bases, and the file base callers upload to and download
from. Single writer, so **one replica, recreated** (never rolled). Logs and the
mail spool stay in the container and go with the pod.

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
metadata: { name: kurly, namespace: enigma-12-bbs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-enigma-12-bbs, namespace: enigma-12-bbs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/enigma-12-bbs, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: enigma-12-bbs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-enigma-12-bbs, namespace: enigma-12-bbs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-enigma-12-bbs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: enigma-12-bbs, namespace: enigma-12-bbs }
spec:
  serviceAccountName: enigma-12-bbs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/enigma-12-bbs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-enigma-12-bbs, importPath: github.com/metio/kurly/workloads/enigma-12-bbs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: enigma-12-bbs, namespace: enigma-12-bbs }
spec:
  serviceAccountName: enigma-12-bbs-deployer
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
        name: enigma-12-bbs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: enigma-12-bbs }
```

<!-- END generated: jaas-deploy -->
