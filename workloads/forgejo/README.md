<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# forgejo

[Forgejo](https://forgejo.org/) — a maintained [Gitea](https://about.gitea.com/)
fork: self-hosted Git repository hosting, issues, pull requests, and a
package/container registry. A plain composable `kurly.http` workload on the
**rootless** image (so kurly's restricted posture fits), with its data on a
PersistentVolume and its database external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local forgejo = import 'github.com/metio/kurly/workloads/forgejo/server.libsonnet';

kurly.list(forgejo(rootUrl='https://git.example.com/'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `forgejo` | |
| `image` | `codeberg.org/forgejo/forgejo:16.0-rootless` | the rootless variant |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the data volume (repos, LFS, config) |
| `dbHost` / `dbName` / `dbUser` / `dbSecret` | `forgejo-db-rw` / `forgejo` / `forgejo` / `forgejo-db-app` | the PostgreSQL database — see below |
| `rootUrl` | inferred | the public base URL for links and clone URLs |
| `env` | `{}` | extra `FORGEJO__section__KEY` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and git-over-HTTP on `:3000` and git-over-SSH on `:2222`. Expose
the HTTP port, and route TCP `:2222` for SSH clones:

```jsonnet
kurly.listOf([
  forgejo(rootUrl='https://git.example.com/')
  + kurly.expose.ownGateway('git.example.com', 'istio', tls='forgejo-tls'),
  kurly.certificate('forgejo-tls', ['git.example.com'], 'letsencrypt-prod'),
])
```

## The database (the cnpg pairing)

Forgejo needs **PostgreSQL**, and kurly never mints the Secret holding its
credentials. The defaults pair with the [cnpg-cluster](../cnpg-cluster/) workload:
deploy a CNPG cluster named `forgejo-db`, and Forgejo finds its `forgejo-db-rw`
Service and reads the password from the `-app` Secret CNPG generates (via
`FORGEJO__database__PASSWD__FILE`, so the secret is mounted, never baked into env).

```jsonnet
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf([
  cnpg(name='forgejo-db', database='forgejo'),
  forgejo(rootUrl='https://git.example.com/'),
])
```

Point `dbHost`/`dbSecret` elsewhere for a database you manage; the Secret must
carry a `password` key (fill it with `kurly.externalSecret` if you don't use CNPG).

## Persistence and scale

One PersistentVolume holds the repositories, so this is **one replica, recreated**
(never rolled) to keep two pods off the ReadWriteOnce volume — the same
single-writer discipline as [tik](../tik/). The generated `app.ini` (with the
instance `SECRET_KEY` and `INTERNAL_TOKEN`) lives on that volume so it survives
restarts, leaving the root filesystem read-only.

For **sessions and OAuth tokens to survive** across pod replacements, provide the
security secrets explicitly rather than letting Forgejo mint ephemeral ones —
through `env`, from a Secret:

```jsonnet
forgejo(env={
  'FORGEJO__security__SECRET_KEY': '...',   // better: from a mounted Secret
  'FORGEJO__oauth2__JWT_SECRET': '...',
})
```

Horizontal scaling (multiple replicas) needs shared (RWX) storage, Redis-backed
sessions ([valkey](../valkey/) or [dragonfly](../dragonfly/)), and the external
database — beyond this recipe's single-writer default.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: forgejo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-forgejo, namespace: forgejo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/forgejo, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: forgejo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-forgejo, namespace: forgejo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-forgejo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: forgejo, namespace: forgejo }
spec:
  serviceAccountName: forgejo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/forgejo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-forgejo, importPath: github.com/metio/kurly/workloads/forgejo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: forgejo, namespace: forgejo }
spec:
  serviceAccountName: forgejo-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: forgejo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: forgejo }
```

<!-- END generated: jaas-deploy -->
