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
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.31')
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

## TLS certificates

The mint end of the same seam: a workload names the TLS Secret it terminates on
(an exposure's `tls`, keycloak's `tlsSecret`) and authors none. `kurly.certificate`
fills that named Secret with a real, auto-renewed certificate by authoring a
cert-manager `Certificate` — point the workload's `tls` parameter at the same
name:

```jsonnet
kurly.listOf([
  kurly.http('storefront', image)
  + kurly.expose.ownGateway('storefront.example.com', 'istio', tls='storefront-tls'),
  kurly.certificate('storefront-tls', ['storefront.example.com'], 'letsencrypt-prod'),
])
```

The Certificate's `secretName` defaults to its own name, so it lands as exactly
the `storefront-tls` the gateway terminates on. `issuerRef` defaults to a
`ClusterIssuer`; name a namespaced `Issuer` with `issuerKind='Issuer'`. The
**prerequisite** is that cert-manager and the named issuer are installed.

## Protecting paths on a Gateway API route

To take a path off the public internet — return 403 on `/admin` while the rest of
the workload serves normally — `ingress-nginx` has configuration-snippet
annotations, but Gateway API has no portable equivalent. The empty-`backendRefs`
trick the spec says returns 404 is honoured inconsistently (Envoy Gateway returns
500), so the dependable answer is to route the path to a small service that always
answers the same way.

The [status-responder](workloads/status-responder/) workload is that service, and
two `expose` modifiers wire it in. Deploy the responder once, globally, and
`kurly.expose.guard` sinks the protected prefixes on the workload's `HTTPRoute` to
it:

```jsonnet
kurly.http('etherpad', image)
+ kurly.expose.listenerSet('pad.example.com', 'shared')
+ kurly.expose.guard(['/admin', '/stats'], 'not-found', serviceNamespace='shared-http-services')
```

Gateway API resolves overlapping matches by specificity, so the guarded prefix
wins over the catch-all for those requests; everything else reaches the workload,
whose own Service stays reachable in-cluster (a `port-forward` still hits
`/admin`). A cross-namespace responder needs consent, granted on its side with
`kurly.expose.referenceGrant(['team-a', 'team-b'])` — see
[status-responder](workloads/status-responder/) for the full pairing.

## DNS records (external-dns)

[external-dns](https://kubernetes-sigs.github.io/external-dns/) already discovers
the hostname of whatever an exposure emits — an Ingress, or (with its
`gateway-httproute` source) an HTTPRoute and its parent Gateway's address — and
creates the record with no help from kurly. Reach for `kurly.expose.dns` only to
**override** what it infers: a different or additional `hostname`, a `ttl`, or a
`target` (the address or CNAME the record points at, rather than the gateway's
own):

```jsonnet
kurly.http('web', image)
+ kurly.expose.ownGateway('web.example.com', 'istio', tls='web-tls')
+ kurly.expose.dns(target='ingress.example.net.', ttl=300)
```

It adds the `external-dns.alpha.kubernetes.io/*` annotations to the right resource
for the exposure — the HTTPRoute for a Gateway API recipe, the Ingress for the
Ingress one — and `annotations` passes through any provider-specific keys
(`cloudflare-proxied`, `aws-weight`, …). The **prerequisite** is external-dns
running with the matching source enabled.

## Black-box probes

`kurly.expose.probe` attaches a prometheus-operator `Probe` to a workload, so
Prometheus black-box-monitors its public URL through a blackbox-exporter — the
outside-in check (does the site actually answer over the network?) that
complements an in-cluster `ServiceMonitor` scrape:

```jsonnet
kurly.http('web', image)
+ kurly.expose.ownGateway('web.example.com', 'istio', tls='web-tls')
+ kurly.expose.probe('web.example.com')
```

`host` is explicit — target a specific health path, whatever the exposure style.
`prober` is the blackbox-exporter address (defaulting to a `blackbox-exporter`
Service), and `module` selects its check (`http_2xx` expects a 2xx). The
**prerequisites** are the prometheus-operator and a blackbox-exporter.

Together with [Secrets](#secrets), [TLS certificates](#tls-certificates), and
[DNS records](#dns-records-external-dns), these are the companions a public-facing
workload composes alongside its exposure — the Secret it reads, the certificate
that fills it, the DNS record that points at it, and the probe that watches it.

## Network policies

`kurly.network` firewalls a workload with an allow-list, on its own axis and with
one recipe per CNI. The rules are written once in a small neutral vocabulary —
`allowFrom`/`allowTo` entries of `{ pods, namespaces | namespace, cidr, ports }` —
and the variant you pick renders them as the matching kind:

```jsonnet
kurly.http('users', image)
+ kurly.network.calico(               // or .kubernetes / .cilium
  allowFrom=[{ pods: { 'app.kubernetes.io/name': 'gateway' }, namespace: 'ingress', ports: [3000] }],
  allowTo=[{ pods: { 'app.kubernetes.io/name': 'postgres' }, namespace: 'databases', ports: [5432] }],
)
```

- `kubernetes` → a `networking.k8s.io/v1` NetworkPolicy
- `calico` → a `projectcalico.org/v3` NetworkPolicy (the aggregated API)
- `cilium` → a `cilium.io/v2` CiliumNetworkPolicy

Each emits one policy named after the workload and selecting its own pods, so the
allow-list is deny-by-default for that pod without a separate rule. All three
share the `networkPolicy` exclusion group — a workload firewalls one way, and
composing two variants fails the render. Anything the neutral vocabulary does not
cover (a Calico `order` or `serviceAccountSelector`, a Cilium L7 block or
`toFQDNs`) passes through verbatim via each variant's `ingress`/`egress`/`extraSpec`
escape hatch, so kurly stays out of modelling the full CNI schemas.

The cluster-wide or per-namespace **default-deny** baseline is a separate choice,
so it is a standalone generator rather than something baked into every workload —
apply it once for the whole cluster, or once per namespace:

```jsonnet
kurly.listOf([ kurly.network.denyAll.calico(global=true) ])   // cluster-wide
kurly.listOf([ kurly.network.denyAll.kubernetes() ])          // this namespace
```

`global=true` (Calico/Cilium) emits the cluster-wide kind; `extraSpec` passes
through the exceptions a real baseline keeps, such as an allow for kube-dns.

## Documentation

The full documentation lives at **<https://kurly.projects.metio.wtf/>**:

- **[Assembler](https://kurly.projects.metio.wtf/assembler/)** — build a workload
  visually and copy out the Jsonnet snippet and JaaS manifests.
- **[Reference](https://kurly.projects.metio.wtf/reference/)** — every kind,
  feature, exposure recipe, network policy variant, and security profile with its
  parameters.
- Workload kinds, features, exposure, security profiles, and how to consume the
  library locally or on Kubernetes with [jaas](https://github.com/metio/jaas).

## License

[0BSD](LICENSE) — see [REUSE.toml](REUSE.toml) for the details.
