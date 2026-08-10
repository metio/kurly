<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongooseim

[MongooseIM](https://github.com/esl/MongooseIM) — an XMPP server built for
messaging at scale, with clustering and a GraphQL management API. A plain
composable `kurly.http` workload on the official image that keeps its Mnesia
database on a PersistentVolume, so it needs no external database by default.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongooseim = import 'github.com/metio/kurly/workloads/mongooseim/server.libsonnet';

kurly.list(mongooseim())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mongooseim` | |
| `image` | `erlangsolutions/mongooseim:6.6.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the Mnesia volume |
| `nodeHost` | `localhost` | the Erlang node's host part — it names the database directory |
| `configMount` | `false` | leave `/member` free for your own config |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves XMPP client (`:5222`), server-to-server (`:5269`) and the HTTP listener
carrying BOSH (`/http-bind`) and WebSocket (`/ws-xmpp`) on `:5280`. Route the XMPP
ports as TCP through a LoadBalancer or a Gateway `TCPRoute`, and compose an HTTP
exposure onto `:5280` for browser clients:

```jsonnet
mongooseim() + kurly.expose.gateway('xmpp.example.com', 'istio', port=5280)
```

## Configuration

The image ships a working `mongooseim.toml` serving the `localhost` domain, which
is enough to boot and nothing you would run a network on. `/member` is the drop-in
directory the entrypoint reads: `mongooseim.toml`, `app.config`, `vm.args` and
`vm.dist.args` found there are symlinked over the shipped ones on every start.

It is a scratch volume by default, because the entrypoint changes into it. Pass
`configMount=true` to leave the path free and mount your own:

```jsonnet
mongooseim(configMount=true) + kurly.config('/member', { 'mongooseim.toml': importstr './mongooseim.toml' })
```

Set your XMPP domains in `general.hosts`, and remember the GraphQL admin listeners
the shipped configuration carries: `:5551` on loopback and `:5541` on all
interfaces, both with the sample `admin`/`secret` credentials. Neither is published
by this workload, and neither should be reachable with those credentials.

## The node name is pinned

The entrypoint derives the Erlang node from `hostname -s` and puts the database in
`/var/lib/mongooseim/Mnesia.<node>`. With the pod name as the hostname, every
replacement pod picks a **new directory on the same volume** and starts empty while
the previous accounts sit there unread — a server that loses its users on a restart
and reports nothing wrong. `NODE_HOST` is therefore fixed (`localhost` by default);
changing it moves the database with it.

## A writable image tree, and the account that owns it

The entrypoint rewrites the release's own `etc/` in place with `sed -i` — `vm.args`
for the node name, `app.config` for the Mnesia and log paths — and the release
creates `var/` and `log/` beside it as it boots. All of that is inside the image
and outside any volume, so the root filesystem is writable here.

The pod runs as **1001:1002**, the account those files belong to. Running as root
instead looks like the obvious answer and does not work: with all capabilities
dropped there is no `CAP_DAC_OVERRIDE`, every write into a directory owned by 1001
fails with `EACCES`, and the Erlang VM dies on a logger handler it could not open —
which reads as a configuration error rather than a permission one. The rest of the
hardened posture (non-root, no privilege escalation, all capabilities dropped, its
own user namespace, `RuntimeDefault` seccomp) holds.

## Persistence and clustering

One Mnesia database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two nodes off the same files. MongooseIM does cluster, but a
cluster wants a StatefulSet with per-pod volumes and the entrypoint's `JOIN_CLUSTER`
handshake against a stable primary — beyond this recipe's default.

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
metadata: { name: kurly, namespace: mongooseim }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mongooseim, namespace: mongooseim }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mongooseim, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mongooseim }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mongooseim, namespace: mongooseim }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mongooseim } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mongooseim, namespace: mongooseim }
spec:
  serviceAccountName: mongooseim-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mongooseim/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mongooseim, importPath: github.com/metio/kurly/workloads/mongooseim }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mongooseim, namespace: mongooseim }
spec:
  serviceAccountName: mongooseim-deployer
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
        name: mongooseim
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mongooseim }
```

<!-- END generated: jaas-deploy -->
