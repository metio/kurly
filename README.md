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
  kurly.web.new('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  .withReplicas(3)
  .withHttpProbes('/')
  .withHost('shop.example.com')
)
```

renders a Deployment, a Service, and an Ingress, ready for
`kubectl apply --filename -`.

## Workload kinds

| Kind | Manifests | For |
|---|---|---|
| `kurly.web` | Deployment + Service + Ingress (via `withHost`) | HTTP workloads reachable from outside the cluster |
| `kurly.api` | Deployment + Service | HTTP workloads for in-cluster consumers |
| `kurly.worker` | Deployment | queue consumers, background processors |
| `kurly.cron` | CronJob | scheduled jobs (`new` requires a schedule) |
| `kurly.daemon` | DaemonSet | per-node agents |

Every kind shares the same modifiers (`withEnv`, `withLabels`,
`withResources`, `withServiceAccount`, `withHttpProbes`, …) plus per-kind ones
like `withReplicas`, `withHost`, or `withSchedule`. Security escape hatches —
`withRootUser`, `withWritableRootFilesystem`, `withHostUsers` — each downgrade
exactly one `restricted` default for the workloads that genuinely need it.

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
