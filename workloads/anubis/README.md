<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# anubis

[Anubis](https://github.com/TecharoHQ/anubis) — sits in front of another service
and makes every unrecognised client solve a proof-of-work challenge before the
request is forwarded, which is what keeps a scraper fleet off an application that
cannot take the load. A plain composable `kurly.http` workload on the official
image.

One Anubis per protected service: it proxies to exactly one upstream. Expose
Anubis instead of the service it protects — an Ingress or HTTPRoute still
pointing at the backend routes straight past the challenge.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local anubis = import 'github.com/metio/kurly/workloads/anubis/server.libsonnet';

kurly.list(
  anubis(target='http://forgejo:3000', cookieDomain='example.com')
  + kurly.expose.gateway('git.example.com', 'envoy-external')
)
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `anubis` | |
| `image` | `ghcr.io/techarohq/anubis:v1.26.2` | |
| `target` | `http://localhost:3923` | the service a passing request is forwarded to |
| `difficulty` | `4` | every increment doubles the work — paid by visitors too |
| `cookieDomain` | unset | the registrable domain (`example.com`), never the host |
| `cookieSecure` | `true` | a browser drops a Secure cookie over plain HTTP |
| `serveRobotsTxt` | `true` | for a backend whose own `robots.txt` cannot be changed |
| `secretName` | `anubis` | holds `ED25519_PRIVATE_KEY_HEX` |

## Supply the Secret

`ED25519_PRIVATE_KEY_HEX` signs the challenge passes. Anubis generates one when
it is unset, and that is worse than it sounds: every restart invalidates every
pass issued so far, and each replica rejects the passes its siblings hand out, so
visitors are challenged again on every request that lands elsewhere. Supplying
the key is what makes more than one replica work at all.

```shell
kubectl create secret generic anubis \
  --from-literal=ED25519_PRIVATE_KEY_HEX="$(openssl rand -hex 32)"
```

## Health lives on the metrics port

The probes read `/healthz` on `:9090`, not the proxy port. A request to `:8923`
is answered by whatever `target` names, or by a challenge page — neither says
anything about Anubis being up, and a probe following the challenge would kill a
perfectly healthy pod. `:9090` also carries the Prometheus metrics, which is why
it is published on the Service.

## Behind a load balancer

Anubis identifies clients by their address, so the proxy in front of it has to
pass one through: without `X-Real-Ip` (or a trusted `X-Forwarded-For`) every
visitor looks like the ingress controller. Envoy Gateway does not set it by
default — add it on the `HTTPRoute` or the `ClientTrafficPolicy`.

## Stateless

Challenges live in memory, so no PersistentVolume and a rolling Deployment. With
the signing key in the Secret, any replica count is safe.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: anubis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-anubis, namespace: anubis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/anubis, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: anubis }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-anubis, namespace: anubis }
spec: { sourceRef: { kind: OCIRepository, name: kurly-anubis } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: anubis, namespace: anubis }
spec:
  serviceAccountName: anubis-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/anubis/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-anubis, importPath: github.com/metio/kurly/workloads/anubis }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: anubis, namespace: anubis }
spec:
  serviceAccountName: anubis-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: anubis
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: anubis }
```

<!-- END generated: jaas-deploy -->
