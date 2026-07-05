<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kurly

A bookstore of Kubernetes workload recipes, written in Jsonnet on top of
[k8s-libsonnet](https://github.com/jsonnet-libs/k8s-libsonnet). Pick a kind,
give it a name and an image, chain modifiers — the result is a set of
manifests with the Pod Security Standards `restricted` profile baked in:
non-root, seccomp `RuntimeDefault`, all capabilities dropped, read-only root
filesystem, its own user namespace (`hostUsers: false`), and no ServiceAccount
token unless a ServiceAccount is configured.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';

kurly.list(
  kurly.http.new('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  .withReplicas(3)
  .withHttpProbes('/')
  + kurly.expose.gateway('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure')
)
```

renders a Deployment, a Service, and an HTTPRoute attached to the platform
team's Gateway, ready for `kubectl apply --filename -`.

## Workload kinds

| Kind | Manifests | For |
|---|---|---|
| `kurly.http` | Deployment + Service | HTTP workloads; compose an `expose` recipe to accept outside traffic |
| `kurly.worker` | Deployment | queue consumers, background processors |
| `kurly.cron` | CronJob | scheduled jobs (`new` requires a schedule) |
| `kurly.daemon` | DaemonSet | per-node agents |

Every kind shares the same modifiers (`withEnv`, `withLabels`,
`withResources`, `withServiceAccount`, `withHttpProbes`, …) plus per-kind ones
like `withReplicas` or `withSchedule`.

## Exposure recipes

Exposure is a separate axis from the workload: compose one (or several — an
Ingress→Gateway migration can run both) onto a `kurly.http` app with `+`.
Every Gateway API recipe emits an HTTPRoute; the `own*` recipes additionally
generate the parent it attaches to.

| Recipe | Emits | For |
|---|---|---|
| `expose.ingress(host, ingressClass=)` | Ingress | clusters on the Ingress API |
| `expose.gateway(host, name, gatewayNamespace=, sectionName=)` | HTTPRoute | attaching to an existing shared Gateway (the usual setup) |
| `expose.listenerSet(host, name, listenerSetNamespace=, sectionName=)` | HTTPRoute | attaching to an existing ListenerSet |
| `expose.ownGateway(host, gatewayClass)` | Gateway + HTTPRoute | clusters without a shared Gateway |
| `expose.ownListenerSet(host, gateway, gatewayNamespace=)` | ListenerSet + HTTPRoute | bringing your own listener to a shared Gateway (it must allow ListenerSets via `spec.allowedListeners`) |

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
kurly.http.new('erp', 'ghcr.io/example/erp:5.4.1') + kurly.security.baseline
```

A profile sets every security knob, so when several compose the last one
wins. For single-knob adjustments the escape hatches — `withRootUser`,
`withWritableRootFilesystem`, `withHostUsers` — each downgrade exactly one
default; chain them *after* a profile to fine-tune it.

## Rollout stages and migrations

A workload deployed through [stageset-controller](https://github.com/metio/stageset-controller)
rolls through stages and may need version-gated migrations at boundaries.
Both are declared next to the workload:

```jsonnet
kurly.stageLists(shop, {
  dev: { config+:: { replicas: 1 } },
  production: { config+:: { replicas: 3 } }
              + kurly.expose.gateway('shop.example.com', 'shared-gateway'),
})
```

renders a map of stage name → `kind: List`, and a migration ladder is a plain
array of `kurly.migrations.migration(name, to, from=, stage=, actions=)`
entries (actions are stageset-controller `Action` objects, passed through
verbatim).

Workloads live as directories under `workloads/` (`stages.jsonnet` +
`migrations.jsonnet`, see `workloads/shop/`), and each is a **release unit of
its own**: it publishes as `ghcr.io/metio/kurly/workloads/<name>`, tagged and
changelogged independently of the library and of every other workload. Each
workload image is **one OCI image with one layer per stage** plus a layer for
the migration ladder, each under its own media type. A Flux `OCIRepository`
selects exactly one stage:

```yaml
spec:
  layerSelector:
    mediaType: application/vnd.metio.stage.production.tar+gzip
    operation: extract
```

and the `application/vnd.metio.migrations.tar+gzip` layer feeds a StageSet's
`spec.migrationsSourceRef`. One image means one version, one signature, and
one changelog entry covering every stage of a rollout. Always set
`layerSelector` on these images — without it Flux extracts whichever layer
comes first.

## Consuming

- **Locally**: `jb install github.com/metio/kurly@main` and render with
  `jsonnet -J vendor`.
- **On Kubernetes with [jaas](https://github.com/metio/jaas)**: the library
  ships as the single-layer OCI image `ghcr.io/metio/kurly` (cosign-signed,
  `:latest` plus dated tags), consumable as a Flux `OCIRepository` source
  behind a `JsonnetLibrary`, or as an image-volume mount. Register the JOI
  [k8s-libsonnet image](https://github.com/metio/jsonnet-oci-images) alongside
  it — kurly imports k8s-libsonnet at render time and does not bundle it.

## License

[0BSD](LICENSE) — see [REUSE.toml](REUSE.toml) for the details.
