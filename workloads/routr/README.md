<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# routr

[Routr](https://routr.io) — a SIP proxy, registrar and location server: it
registers phones and routes calls between them and the carriers you trunk to. A
composable `kurly.http` workload on the all-in-one image, used for its Deployment
and Service plumbing — Routr speaks SIP, not HTTP.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local routr = import 'github.com/metio/kurly/workloads/routr/server.libsonnet';

kurly.list(routr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `routr` | |
| `image` | `docker.io/fonoster/routr-one:2.9.1` | |
| `databaseUrl` | the PostgreSQL inside the image | see below |
| `externalAddr` | unset | the address other SIP endpoints reach this proxy at |

## Ports

| port | protocol | what |
|---|---|---|
| 5060 | TCP + UDP | SIP |
| 5061 | TCP | SIP over TLS |
| 5062 | TCP | SIP over WebSocket |
| 5063 | TCP | SIP over secure WebSocket |
| 51908 | TCP | the gRPC management API |

Route the SIP ports as TCP/UDP through a LoadBalancer or a Gateway
`TCPRoute`/`UDPRoute` — an HTTP ingress cannot carry them. The management API
has no authentication of its own here; keep it inside the cluster.

SIP carries addresses in its own messages, so a proxy behind NAT or a rewriting
load balancer has to be told the address callers reach it at. That is
`externalAddr`; without it Routr advertises the pod address and a phone outside
the cluster sends its media nowhere.

## No volume, deliberately

The all-in-one image carries an **already initialized** PostgreSQL in its own
filesystem and starts it at boot, and the tooling that created it (npm, prisma,
the migrations) is deleted from the released image. A PersistentVolume mounted
over `/var/lib/postgresql/data` therefore hides a database cluster that nothing
left in the image can rebuild.

So agents, domains, trunks and numbers live for as long as the pod does, and are
configured through the API after each start. Point `databaseUrl` at a PostgreSQL
you keep — the `cnpg-cluster` workload provides one — and the same configuration
survives a restart.

Registrations are held in an in-memory location service either way, so this is
**one replica, recreated**: a second would answer for phones it has never seen.

## Less hardened, deliberately

The entrypoint starts the bundled PostgreSQL and then `su-exec`s down to the
service account, which it can only do from root. The root filesystem is writable
because the same entrypoint rewrites `config/edgeport.yaml` in place, mints the
signaling keystore into `/etc/routr/certs`, and hands PostgreSQL its data
directory and socket — all inside the image's own tree.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: routr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-routr, namespace: routr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/routr, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: routr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-routr, namespace: routr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-routr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: routr, namespace: routr }
spec:
  serviceAccountName: routr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/routr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-routr, importPath: github.com/metio/kurly/workloads/routr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: routr, namespace: routr }
spec:
  serviceAccountName: routr-deployer
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
        name: routr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: routr }
```

<!-- END generated: jaas-deploy -->
