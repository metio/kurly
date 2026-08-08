<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# citadel

[Citadel](https://www.citadel.org/) — groupware with mail, calendars, address
books, forums and instant messaging in one server, reached through its own web
interface or through the standard mail and chat protocols. A composable
`kurly.http` workload; everything Citadel keeps lives in one directory on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local citadel = import 'github.com/metio/kurly/workloads/citadel/server.libsonnet';

kurly.list(citadel())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `citadel` | |
| `image` | `citadeldotorg/citadel:1022` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/citadel-data` |
| `env` / `resources` / `labels` / `annotations` | | |

## Ports

The web interface is on `:80` (`http`) — compose an exposure onto it. Beside it
the Service carries `https` (443), `smtp` (25), `smtps` (465), `submission`
(587), `imap` (143), `imaps` (993), `pop3` (110), `pop3s` (995), `xmpp` (5222)
and `citadel` (504). Those are TCP protocols an Ingress or an HTTPRoute cannot
carry: route them through a LoadBalancer Service or a Gateway `TCPRoute`.

Delivering and receiving mail also needs a stable public address, forward and
reverse DNS that agree, and SPF/DKIM/DMARC records for the domain. None of that
is something this workload can arrange for you.

## Persistence

The database, the message store, the configuration and the TLS material all live
under `/citadel-data`. One Berkeley DB message store on a ReadWriteOnce volume,
so this is **one replica, recreated** (never rolled) — two servers opening the
same database is how it gets corrupted.

## Less hardened, deliberately

`ctdlvisor` supervises `citserver` and `webcit`, binds the privileged mail and
web ports, and drops to Citadel's own account itself — which it can only do
starting from root.

## Probes

By connection, not by path: the web interface redirects an anonymous caller into
its login flow, and first start creates the database and the default rooms before
anything answers, which is what the startup probe's budget is for.

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
metadata: { name: kurly, namespace: citadel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-citadel, namespace: citadel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/citadel, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: citadel }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-citadel, namespace: citadel }
spec: { sourceRef: { kind: OCIRepository, name: kurly-citadel } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: citadel, namespace: citadel }
spec:
  serviceAccountName: citadel-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/citadel/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-citadel, importPath: github.com/metio/kurly/workloads/citadel }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: citadel, namespace: citadel }
spec:
  serviceAccountName: citadel-deployer
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
        name: citadel
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: citadel }
```

<!-- END generated: jaas-deploy -->
