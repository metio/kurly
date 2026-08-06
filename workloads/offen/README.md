<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# offen

[Offen Fair Web Analytics](https://github.com/offen/offen) — lightweight web
analytics where the people being measured can see, and delete, the data collected
about them. A plain composable `kurly.http` workload; accounts and events live in
a SQLite database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local offen = import 'github.com/metio/kurly/workloads/offen/server.libsonnet';

kurly.list(offen())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `offen` | |
| `image` | `offen/offen:v1.4.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/opt/offen` |
| `secretName` | `offen` | holds `OFFEN_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

## It serves on :3000, not :80

The image defaults to `:80` and gets there with a **file capability**
(`CAP_NET_BIND_SERVICE` set on the binary), which a container that drops all
capabilities never receives. Rather than relax the hardened posture for a port
number, this stage sets `OFFEN_SERVER_PORT=3000` and declares that port. TLS and
the public name belong to the exposure you compose on top, so Offen's own
`autotls` stays off.

## The Secret

`secretName` names a Secret holding `OFFEN_SECRET`, the key that signs sessions
and cookies. Without it Offen mints a random one at startup, so **every restart
logs everybody out** — supplying it is what makes sessions survive a rollout. Any
32 random bytes, base64-encoded, will do; the binary's own `offen secret`
subcommand prints one in the expected shape.

## Accounts

Offen has no sign-up page. Create the first account inside a running pod:

```shell
kubectl exec deploy/offen -- offen setup \
  -email you@example.com -name "My Site" -password '…'
```

Everything after that — further accounts, the share links, the retention
period — happens in the account interface.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled): two pods writing the same database file is how a
SQLite store gets corrupted.

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
metadata: { name: kurly, namespace: offen }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-offen, namespace: offen }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/offen, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: offen }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-offen, namespace: offen }
spec: { sourceRef: { kind: OCIRepository, name: kurly-offen } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: offen, namespace: offen }
spec:
  serviceAccountName: offen-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/offen/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-offen, importPath: github.com/metio/kurly/workloads/offen }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: offen, namespace: offen }
spec:
  serviceAccountName: offen-deployer
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
        name: offen
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: offen }
```

<!-- END generated: jaas-deploy -->
