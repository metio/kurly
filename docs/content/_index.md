---
title: kurly
description: A Jsonnet library of composable Kubernetes workload recipes, hardened by default.
---

A bookstore of Kubernetes workload recipes, written in Jsonnet on top of
[k8s-libsonnet](https://github.com/jsonnet-libs/k8s-libsonnet). Start from a
kind, then add capabilities as composable `+` features — the result is a set of
manifests with the Pod Security Standards `restricted` profile baked in:
non-root, seccomp `RuntimeDefault`, all capabilities dropped, read-only root
filesystem, its own user namespace (`hostUsers: false`), and no ServiceAccount
token unless a ServiceAccount is configured.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';

kurly.list(
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  + kurly.replicas(3)
  + kurly.probes('/')
  + kurly.expose.gateway('storefront.example.com', 'shared-gateway', gatewayNamespace='infrastructure')
)
```

renders a Deployment, a Service, and an HTTPRoute attached to the platform
team's Gateway, ready for `kubectl apply --filename -`. Every feature is a
`{ config+:: … }` mixin, so they late-bind against the merged config and compose
in any order.

Two fast ways in: build a workload visually in the
**[Assembler](/assembler/)** and copy out the snippet and JaaS manifests, or
browse every kind, feature, and recipe in the **[Reference](/reference/)**.

## Workload kinds

Each kind is a `function(name, image)` (cron also takes a schedule) — the base
"default" you add features onto.

| Kind | Manifests | For |
|---|---|---|
| `kurly.http` | Deployment + Service | HTTP workloads; compose an `expose` recipe to accept outside traffic |
| `kurly.worker` | Deployment | queue consumers, background processors |
| `kurly.cron` | CronJob | scheduled jobs (`kurly.cron(name, image, schedule)`) |
| `kurly.daemon` | DaemonSet | per-node agents |

## Features

Add capabilities with `+`. Common ones: `kurly.replicas`, `kurly.env`,
`kurly.args` / `kurly.command`, `kurly.port`, `kurly.probes`,
`kurly.resources`, `kurly.labels`, `kurly.annotations`,
`kurly.serviceAccount`. For stateful and configured workloads:

| Feature | Adds |
|---|---|
| `kurly.store(mountPath, size, storageClass=, accessModes=)` | an owned PersistentVolumeClaim, mounted |
| `kurly.config(files, mountPath=)` | a ConfigMap from a filename→content map, mounted read-only |
| `kurly.secretMount(secretName, mountPath, optional=, defaultMode=)` | mounts an **existing** Secret read-only (kurly never mints key material) |
| `kurly.scratch(mountPath, sizeLimit=)` | a writable `emptyDir` (the escape valve a read-only root filesystem needs) |
| `kurly.runAs(uid, gid=, fsGroup=)` | pins a non-root uid/gid and the fsGroup so the pod owns a mounted volume |
| `kurly.recreate()` | the `Recreate` update strategy — for a single writer on a ReadWriteOnce store |

```jsonnet
kurly.http('tik', 'ghcr.io/metio/tik:2026.7.14174051')
+ kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
+ kurly.store('/var/lib/tik', '1Gi')
+ kurly.config({ 'pipelines.edn': pipelines }, mountPath='/etc/tik')
+ kurly.secretMount('tik-signing-key', '/etc/tik-key', optional=true)
+ kurly.runAs(12345)
+ kurly.recreate()
```

Every parameter and default is in the [Reference](/reference/).

## Exposure recipes

Exposure is a separate axis from the workload: compose **exactly one** onto a
`kurly.http` app with `+`. Every Gateway API recipe emits an HTTPRoute; the
`own*` recipes additionally generate the parent it attaches to.

| Recipe | Emits | For |
|---|---|---|
| `expose.ingress(host, ingressClass=)` | Ingress | clusters on the Ingress API |
| `expose.gateway(host, name, gatewayNamespace=, sectionName=)` | HTTPRoute | attaching to an existing shared Gateway (the usual setup) |
| `expose.listenerSet(host, name, listenerSetNamespace=, sectionName=)` | HTTPRoute | attaching to an existing ListenerSet |
| `expose.ownGateway(host, gatewayClass)` | Gateway + HTTPRoute | clusters without a shared Gateway |
| `expose.ownListenerSet(host, gateway, gatewayNamespace=)` | ListenerSet + HTTPRoute | bringing your own listener to a shared Gateway (it must allow ListenerSets via `spec.allowedListeners`) |

All five join the `exposure` exclusion group, so composing two of them **fails
the render** — a workload routes one way, and the mistake never reaches a
cluster. (An Ingress→Gateway migration runs the two as separate apps instead.)

## Security profiles

Every kind ships the Pod Security Standards `restricted` profile by default,
so composing a profile only ever relaxes the posture — for the images that
genuinely can't run under `restricted`:

| Profile | Effect |
|---|---|
| `security.restricted` | the default, written out — compose it after another profile to re-tighten |
| `security.baseline` | allows root, the image's stock capabilities, privilege escalation, and an unpinned seccomp profile; the extra hardening beyond PSS (read-only root filesystem, user namespaces) stays on |
| `security.privileged` | emits no security fields at all |

```jsonnet
kurly.http('erp', 'ghcr.io/example/erp:5.4.1') + kurly.security.baseline
```

A profile sets every security knob, so when several compose the last one
wins. For single-knob adjustments the escape-hatch features — `kurly.rootUser`,
`kurly.writableRootFilesystem`, `kurly.hostUsers` — each downgrade exactly one
default; compose them *after* a profile to fine-tune it.

## Workloads

A **workload** is a deployable app built from the recipes, released as its own
OCI image and deployed by JaaS and stageset-controller. Each lives under
`workloads/<name>/` as one `<stage>.libsonnet` per stage — a `function(params)`
returning a **composable app** (a base with sensible defaults, exposure left to
you), plus a `migrations.jsonnet` ladder and a `README.md`. A consumer imports a
stage, adapts it with `+` features, and renders with `kurly.list`:

```jsonnet
local tik = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';
kurly.list(tik() + kurly.expose.gateway('tik.internal', 'shared-gateway'))
```

Stages are the ordered **install phases of one application** (apply a phase,
gate it healthy, then the next), not environment tiers — one stage file maps to
one stageset stage. Many workloads need only **one** stage; don't manufacture
ordering an application lacks (a PVC that binds WaitForFirstConsumer must ride
with the pod that consumes it, so it can't be gated into a stage of its own). A
migration ladder is a plain array of
`kurly.migrations.migration(name, to, from=, stage=, actions=)` entries (actions
are stageset-controller `Action` objects, passed through verbatim).

Each workload is a **release unit of its own** — it publishes as
`ghcr.io/metio/kurly/workloads/<name>`, tagged and changelogged independently of
the library and every other workload. The artifact is the workload's jsonnet
**SOURCE**, not pre-rendered manifests: a **single-layer** `FROM scratch`
vendor-tree image (the same shape as the library and JOI images), which JaaS
renders with the consumer's parameters. It carries a `version` constant the
release rewrites from `dev` to the calver, stamped as `app.kubernetes.io/version`.
The full deploy — import → `JsonnetSnippet` → `StageSet` — is in each workload's
[README on GitHub](https://github.com/metio/kurly/blob/main/workloads/tik/README.md).

## Assembling with conditionals

`kurly.list(app)` renders one composed app. To build a set from several parts —
some optional, some themselves lists — use `kurly.listOf`, which drops `null`
entries and flattens nested arrays. A Jsonnet `if` with no `else` is `null` when
false, so an unmet condition simply drops out:

```jsonnet
kurly.listOf([
  kurly.list(app).items,                  // a group, flattened in
  if enableBackup then backupCronJob,     // dropped when the flag is false
  sharedConfigMap,
])
```

`kurly.join` is the same drop-and-flatten over a plain array, for assembling any
value (a set of args, an env list) the same way.

## Consuming

- **Locally**: `jb install github.com/metio/kurly@main` and render with
  `jsonnet -J vendor`.
- **On Kubernetes with [jaas](https://github.com/metio/jaas)**: the library
  ships as the single-layer OCI image `ghcr.io/metio/kurly` (cosign-signed,
  `:latest` plus dated tags), consumable as a Flux `OCIRepository` source
  behind a `JsonnetLibrary`, or as an image-volume mount. Register the JOI
  [k8s-libsonnet image](https://github.com/metio/jsonnet-oci-images) alongside
  it — kurly imports k8s-libsonnet at render time and does not bundle it.
