<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kurly

A bookstore of Kubernetes workload recipes, written in Jsonnet on top of
[k8s-libsonnet](https://github.com/jsonnet-libs/k8s-libsonnet). Start from a
kind (`http`, `worker`, `cron`, `daemon`), then add capabilities as composable
`+` features — the result is a set of manifests with the Pod Security Standards
`restricted` profile baked in.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';

kurly.list(
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  + kurly.replicas(3)
  + kurly.expose.gateway('storefront.example.com', 'shared-gateway')
)
```

## Documentation

The full documentation lives at **<https://kurly.projects.metio.wtf/>**:

- **[Assembler](https://kurly.projects.metio.wtf/assembler/)** — build a workload
  visually and copy out the Jsonnet snippet and JaaS manifests.
- **[Reference](https://kurly.projects.metio.wtf/reference/)** — every kind,
  feature, exposure recipe, and security profile with its parameters.
- Workload kinds, features, exposure, security profiles, and how to consume the
  library locally or on Kubernetes with [jaas](https://github.com/metio/jaas).

## License

[0BSD](LICENSE) — see [REUSE.toml](REUSE.toml) for the details.
