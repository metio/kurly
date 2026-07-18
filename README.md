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
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.30')
  + kurly.replicas(3)
  + kurly.expose.gateway('storefront.example.com', 'shared-gateway')
)
```

## Private registries

A cluster that pulls from a private registry needs two things: the images pointed
at it, and the credentials to pull them.

```jsonnet
kurly.mirror('harbor.internal/dockerhub', kurly.list(
  cache() + kurly.imagePullSecrets(['regcred'])
))
```

`kurly.mirror` swaps the registry on every image in the rendered output —
`docker.io/valkey/valkey:9.0.3` becomes
`harbor.internal/dockerhub/valkey/valkey:9.0.3`, with the repository, tag and
digest carried through. It works on the rendered manifests rather than on the
config because a workload's images are not all reachable from config: an
initContainer's spec is passed through verbatim, a sidecar can be grafted on with
the raw `+` escape hatch, and a custom resource's image is a field of someone
else's API. `kurly.image()` reaches none of those — it changes the main container
and leaves the rest pulling from the public internet, which on a private-registry
cluster means the pod never starts.

`kurly.imagePullSecrets` is pod-level, so it covers the main container, the init
containers and the sidecars together. A custom resource has no pod to attach it
to, so those carry their own knob — see
[cnpg-cluster](workloads/cnpg-cluster/#pulling-from-a-private-registry).

`mirror` reaches every image kurly renders, which for a custom resource is every
image in the resource — but an operator may pull images the resource never names.
CloudNativePG bootstraps each PostgreSQL pod with its own image, configured on
the operator rather than on the Cluster, so a workload backed by an operator
needs that operator pointed at the registry too.

If the private registry is a **transparent mirror** — a containerd registry
mirror, or a pull-through cache configured on the nodes — none of this is needed:
the nodes redirect `docker.io/…` themselves, and rewriting references only adds
drift. Reach for `mirror` when the registry renames the path, as a proxy-cache
project does, or when the copy is air-gapped.

## Secrets

kurly never creates a Secret. Every workload that needs one names it and expects
someone — or something — else to author it: the cluster operator, an operator
that mints its own credentials (CloudNativePG, Grafana), a sealed secret, or
External Secrets Operator. This is a policy invariant, not a convention — a
recipe that rendered a Secret would fail the build. Referencing by name is what
makes any Secret swappable: whatever fills the named Secret, the workload is
indifferent.

That makes the [External Secrets Operator](https://external-secrets.io/) a
first-class fit. Point `kurly.externalSecret` at the same name a workload
references, and ESO reconciles the values in from your store (Vault, AWS/GCP
Secrets Manager, …):

```jsonnet
kurly.listOf([
  loki(storageSecret='loki-storage'),
  kurly.externalSecret('loki-storage', { name: 'vault', kind: 'ClusterSecretStore' }, [
    { secretKey: 'access_key_id',     remoteRef: { key: 'loki/s3', property: 'access_key_id' } },
    { secretKey: 'access_key_secret', remoteRef: { key: 'loki/s3', property: 'access_key_secret' } },
  ]),
])
```

The target Secret takes the ExternalSecret's own name, so it lands as exactly the
`loki-storage` the workload names — nothing else to wire. The `secretStoreRef`
and the data entries pass through verbatim; kurly does not model ESO's remoteRef
schema (`dataFrom`, generators, `template`), which would only drift against its
API. The **prerequisite** is that ESO and a `SecretStore`/`ClusterSecretStore`
are already installed in the cluster.

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
