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
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.31')
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
| `kurly.stateful` | StatefulSet + headless Service | stable identity and per-pod storage (`store` becomes a volumeClaimTemplate) |
| `kurly.job` | Job | one-off tasks that run to completion |

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
wins. For single-knob adjustments the escape-hatch features each downgrade
exactly one default; compose them *after* a profile to fine-tune it.

| Hatch | What it relaxes | What to know |
|---|---|---|
| `kurly.rootUser` | drops `runAsNonRoot` | it does **not** set a uid — the container runs as the image's own `USER`. To pin uid 0 explicitly, add `kurly.runAs(0)`; `kurly.runAs(0)` on its own fails the render, because a zero uid under `runAsNonRoot` is a container the kubelet refuses to start. |
| `kurly.writableRootFilesystem` | drops `readOnlyRootFilesystem` | the container may write anywhere in its image, not only into mounted volumes. |
| `kurly.hostUsers` | drops `hostUsers: false` | the pod then shares the **host** user namespace — see the portability note below. |

### The user-namespace default and where it doesn't run

Every kind sets `hostUsers: false`, so a pod runs in its **own** user
namespace: its root maps to an unprivileged host uid, and a container breakout
lands as nobody on the node. This is the one hardening default that depends on
the node. It needs a Linux node whose kernel and kubelet support user
namespaces; a **Windows node cannot honour it**, and a cluster with the feature
gate off rejects the field. On those nodes compose `kurly.hostUsers` to drop
back to the shared namespace — the pod loses that isolation but schedules.
`security.baseline` keeps `hostUsers: false`; only `security.privileged`, which
emits no security fields at all, leaves it off without the hatch.

## Running under a service mesh

`kurly.mesh` is a composable axis like `expose` and `network` — one recipe per
mesh, composed onto a workload with `+`:

```jsonnet
kurly.http('app', image) + kurly.mesh.istio()
```

That does two things. It puts the sidecar injection marker on the **pod
template** (never the controller, where the injector would not see it), and it
emits a `security.istio.io/v1` `PeerAuthentication` named after the workload,
selecting its own pods, with `mode: STRICT` — the object that makes the sidecar
**refuse** plaintext rather than merely accept TLS.

For Istio that marker is the **label** `sidecar.istio.io/inject: "true"`, and
the distinction is worth knowing if you have ever set it by hand. Istio's
injection webhook selects on labels only — an `objectSelector` cannot read
annotations — so in a namespace carrying neither `istio-injection` nor
`istio.io/rev`, the annotation form injects nothing, and does so without a word.
Linkerd's injector reads an annotation instead. Which one a mesh wants is the
recipe's business rather than yours.

Your own `podLabels` still win over the recipe's, so opting one workload out of
injection on a mesh-wide cluster is obeyed rather than overwritten:

```jsonnet
kurly.http('app', image) + kurly.mesh.istio()
+ kurly.podLabels({ 'sidecar.istio.io/inject': 'false' })
```

`podLabels` and `podAnnotations` land on the pod template only, never on the
controller's immutable selector, which is what makes composing a mesh onto a
running workload an ordinary rollout: a selector that changed would need a
delete and reinstall.

Each half can be turned off on its own. `mtls=null` emits no
`PeerAuthentication`, leaving the namespace or mesh default in force;
`inject=false` skips the marker, for a cluster that labels the namespace
instead. Per-port overrides go through `peerAuthentication`, merged verbatim
into the emitted spec.

For the namespace-wide floor — every pod, not just this workload — there is a
standalone generator, placed with `kurly.list` the way `network.denyAll` is. A
workload does not emit one of these itself; it would be legislating for its
neighbours:

```jsonnet
kurly.list([app, kurly.mesh.strictNamespace()])
```

Recipes join the `mesh` exclusion group, so a workload cannot compose two meshes.

Every workload in the catalogue that takes composed features — 255 of the 273
stages — renders with a mesh composed onto it, and the gate checks each one: the
injection marker reaches every pod template the stage renders, and the emitted
`PeerAuthentication` selects those pods. Both are ways a mesh can fail to reach a
workload while the manifest set looks perfectly correct — an unmarked pod gets no
sidecar and says nothing about it, and a policy that selects nothing enforces
mTLS on nothing. The remaining 18 stages render a custom resource, so their pod
metadata goes through the operator's own parameter instead.

### What kurly does not emit

**No `AuthorizationPolicy`.** Which principals may call which paths of a
workload depends on what else the tenant runs, so it is not something a workload
recipe knows — and Istio's authorization schema is large and moves. That is the
same restraint the network axis takes with the CNI schemas: model the small
stable thing, and pass the rest through verbatim.

A workload whose stage renders a **custom resource** cannot take a composed
feature — it says so at render rather than accepting one and doing nothing — so
its pod metadata goes through the parameter the operator honours instead. The
shape differs per operator: `podMetadata` on a Prometheus, `inheritedMetadata` on
a CNPG Cluster.

```jsonnet
(import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet')(
  annotations={ 'sidecar.istio.io/inject': 'true' },
)
```

Cilium needs no injection at all, and its policy side is already a kurly axis:
`kurly.network.cilium(...)` emits a `CiliumNetworkPolicy` from the same
allow-list vocabulary the Kubernetes and Calico variants use.

### What the mesh costs at admission, and where to put that cost

Composing a mesh changes what runs, so it changes what an admission baseline
sees. Measured against every [bollwerk](https://github.com/metio/bollwerk) policy
on a live API server — the same workload deployed twice, meshed and bare, so the
answer is the difference rather than a list the workload already earned:

| | policies broken by the injected containers |
|---|---|
| Istio's default install | `disallow-unwanted-capabilities`, `require-run-as-nonroot`, `require-ro-rootfs`, `restrict-image-registries` |
| with Istio's CNI plugin | `restrict-image-registries` |

By default Istio programs each pod's iptables from an `istio-init` container that
runs as root with `NET_ADMIN` and `NET_RAW` — precisely what a hardened baseline
exists to forbid, and it lands in **every meshed pod**. The CNI plugin replaces
that container with an unprivileged `istio-validation`, and the workload's cost
falls to the proxy image's registry not being on the allow-list — a one-line
decision for whoever runs the mesh.

The privilege does not vanish, though; it **moves**. The CNI node agent that now
does the work is itself privileged and breaks nine policies. That is a far better
place for it — one cluster component an operator installs and exempts
deliberately, the way a CSI driver is exempted, instead of a relaxation in every
tenant's pod — but it is a relocation, not a removal, and an operator promising
both an encrypted mesh and an enforced baseline should be told which of the two
they are buying.

`hack/smoke/deep/mesh-bsi.sh` is the measurement; re-run it against a newer Istio
rather than trusting the table.

### Why mTLS needs a rendered object, not a policy

Worth knowing if a compliance regime requires encryption in transit: **no
admission policy can verify that requirement**. A `ValidatingAdmissionPolicy`
sees the object being written — it cannot observe traffic, and it cannot require
that some other object exists elsewhere. So a workload passing every policy in
`bsi` says nothing either way about whether its traffic is encrypted, and an
absent verdict there is not a negative one.

That is exactly the gap a recipe can close. Emitting the enforcing object is
something a renderer can do and an admission controller cannot, and the object
is then evidence in its own right: it is in the manifest set, under version
control, applied by the same reconciler as the workload.

## Workloads

A **workload** is a deployable app built from the recipes, released as its own
OCI image and deployed by JaaS and stageset-controller. Each lives under
`workloads/<name>/` as one `<stage>.libsonnet` per stage — a `function(params)`
returning a **composable app** (a base with sensible defaults, exposure left to
you), plus a `README.md`. A consumer imports a
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

`kurly.list` renders one composed app, or a set assembled from several parts —
apps, standalone manifests, sublists, and optional entries. Apps expand to their
manifests (owned ones included), sublists flatten, and a Jsonnet `if` with no
`else` is `null` when false, so an unmet condition simply drops out:

```jsonnet
kurly.list([
  app,                                    // an app, expanded to its manifests
  if enableBackup then backupCronJob,     // dropped when the flag is false
  sharedConfigMap,                        // a standalone manifest, passed through
])
```

`kurly.join` is the same drop-and-flatten over a plain array, for assembling any
value (a set of args, an env list) the same way.

## Customizing beyond the features

Reach for a named feature first — they cover the common needs ergonomically and
keep your workload a pure function of its config (which is what the
[Reference](/reference/), the assembler, and the tests all rely on). Pod-only
labels and annotations, for network policies or sidecar injection, are features:

```jsonnet
kurly.http('app', image)
+ kurly.podLabels({ 'monitoring/scrape': 'true' })   // pod template only, never the selector
+ kurly.podAnnotations({ 'linkerd.io/inject': 'enabled' })
```

For the long tail kurly does not model, the escape hatch is plain Jsonnet `+` at
your own edge — the workload is just an object whose visible fields are its
manifests:

```jsonnet
kurly.list(
  kurly.http('app', image)
  + { deployment+: { spec+: { minReadySeconds: 30 } } }   // patch any field directly
)
```

When you find yourself reaching for the same patch repeatedly, that is the signal
to promote it to a named feature.

## Consuming

- **Locally**: `jb install github.com/metio/kurly@main` and render with
  `jsonnet -J vendor`.
- **On Kubernetes with [jaas](https://github.com/metio/jaas)**: the library
  ships as the single-layer OCI image `ghcr.io/metio/kurly` (cosign-signed,
  `:latest` plus dated tags), consumable as a Flux `OCIRepository` source
  behind a `JsonnetLibrary`, or as an image-volume mount. Register the JOI
  [k8s-libsonnet image](https://github.com/metio/jsonnet-oci-images) alongside
  it — kurly imports k8s-libsonnet at render time and does not bundle it.
