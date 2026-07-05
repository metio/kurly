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
like `withReplicas` or `withSchedule`. Security escape hatches —
`withRootUser`, `withWritableRootFilesystem`, `withHostUsers` — each downgrade
exactly one `restricted` default for the workloads that genuinely need it.

## Exposure recipes

Exposure is a separate axis from the workload: compose one (or several — an
Ingress→Gateway migration can run both) onto a `kurly.http` app with `+`.
Every Gateway API recipe emits an HTTPRoute; the `own*` recipes additionally
generate the parent it attaches to.

| Recipe | Emits | For |
|---|---|---|
| `expose.ingress(host, ingressClass=)` | Ingress | clusters on the Ingress API |
| `expose.gateway(host, name, gatewayNamespace=, sectionName=)` | HTTPRoute | attaching to an existing shared Gateway (the usual setup) |
| `expose.listenerSet(host, name, listenerSetNamespace=, sectionName=)` | HTTPRoute | attaching to an existing XListenerSet |
| `expose.ownGateway(host, gatewayClass)` | Gateway + HTTPRoute | clusters without a shared Gateway |
| `expose.ownListenerSet(host, gateway, gatewayNamespace=)` | XListenerSet + HTTPRoute | bringing your own listener to a shared Gateway |

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
