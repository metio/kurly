<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# keycloak

[Keycloak](https://www.keycloak.org/) — identity and access management (OIDC,
SAML, SSO) — as an official
[keycloak-operator](https://www.keycloak.org/operator/installation) `Keycloak`
custom resource. Like [loki](../loki/) and [tempo](../tempo/), this authors the CR
directly; the operator reconciles it into a StatefulSet, Services, and the admin
credentials Secret.

**Prerequisite:** the keycloak-operator (its CRDs and controller) installed. Its
recent releases let **one** operator manage `Keycloak` CRs across many namespaces,
so a single cluster-wide install serves every tenant.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local keycloak = import 'github.com/metio/kurly/workloads/keycloak/server.libsonnet';

kurly.list(keycloak(hostname='https://id.example.com', tlsSecret='keycloak-tls'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `keycloak` | |
| `instances` | `1` | replica count |
| `image` | operator's choice | pin for air-gap / a specific Keycloak version |
| `dbHost` / `dbName` / `dbSecret` | `keycloak-db-rw` / `keycloak` / `keycloak-db-app` | the PostgreSQL database — see below |
| `hostname` | inferred | the public URL Keycloak builds links against (required in production) |
| `tlsSecret` | — (plain HTTP) | the cert Keycloak terminates, or omit behind a TLS proxy |
| `spec` | `{}` | extra `Keycloak` spec fields, merged verbatim |

## The database (the cnpg pairing)

Keycloak needs a **PostgreSQL** database, and kurly never mints the Secret holding
its credentials. The defaults pair with the [cnpg-cluster](../cnpg-cluster/)
workload: deploy a CNPG cluster named `keycloak-db`, and Keycloak finds its
read-write Service (`keycloak-db-rw`) and reads the username/password from the
`-app` Secret CNPG generates automatically.

```jsonnet
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf([
  cnpg(name='keycloak-db', database='keycloak'),
  keycloak(hostname='https://id.example.com', tlsSecret='keycloak-tls'),
])
```

For a database elsewhere, set `dbHost`/`dbName`/`dbSecret` to your own. The Secret
must carry `username` and `password` keys — fill it from your secrets store with
`kurly.externalSecret` (see the repository [README](../../#secrets)) if you don't
use CNPG.

## TLS and proxies

`tlsSecret` names the Secret whose certificate Keycloak terminates itself (with
cert-manager, the Secret the issuer writes into). Omitted, Keycloak serves plain
HTTP — correct when a **TLS-terminating gateway or ingress** sits in front, in
which case tell Keycloak to trust the proxy headers so it builds correct URLs:

```jsonnet
keycloak(hostname='https://id.example.com', spec={ proxy: { headers: 'xforwarded' } })
```

Expose it from outside the cluster by composing an exposure onto the operator's
Service, or let the operator manage an Ingress via `spec.ingress`.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-keycloak, namespace: identity }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/keycloak
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-keycloak, namespace: identity }
spec: { sourceRef: { kind: OCIRepository, name: kurly-keycloak } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: keycloak, namespace: identity }
spec:
  serviceAccountName: keycloak-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local keycloak = import 'github.com/metio/kurly/workloads/keycloak/server.libsonnet';
      function(hostname='https://id.example.com')
        kurly.list(keycloak(hostname=hostname, tlsSecret='keycloak-tls'))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,          importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-keycloak, importPath: github.com/metio/kurly/workloads/keycloak }
  tlas:
    - name: hostname
      value: https://id.example.com
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: keycloak, namespace: identity }
spec:
  serviceAccountName: keycloak-deployer
  stages:
    - name: keycloak
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: keycloak
      readyChecks:
        checks:
          - apiVersion: k8s.keycloak.org/v2beta1
            kind: Keycloak
            name: keycloak
```
