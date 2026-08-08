<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# harbor

[Harbor](https://goharbor.io/) — an OCI registry with projects, users, robot
accounts, replication, retention, quotas and signing on top of the upstream
distribution server. Four composable stages, one per Harbor process: `core` (the
API and token service), `portal` (the web UI), `registry` (the distribution
server plus its controller sidecar) and `jobservice` (garbage collection,
replication, retention, webhooks).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local core = import 'github.com/metio/kurly/workloads/harbor/core.libsonnet';
local portal = import 'github.com/metio/kurly/workloads/harbor/portal.libsonnet';
local registry = import 'github.com/metio/kurly/workloads/harbor/registry.libsonnet';
local jobservice = import 'github.com/metio/kurly/workloads/harbor/jobservice.libsonnet';

kurly.list([
  core(externalUrl='https://harbor.example.com'),
  portal(),
  registry(),
  jobservice(),
])
```

All four stages default to the same names, the same Secret (`harbor`), the same
database (`harbor-db-rw`) and the same Redis (`harbor-cache`), so a default
deployment needs no wiring. Rename one and pass the new name to the stages that
address it (`core(registryName=…)`, `jobservice(coreName=…)`).

### `core`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `harbor-core` | |
| `image` | `docker.io/goharbor/harbor-core:v2.15.0` | |
| `externalUrl` | `https://harbor.example.com` | the address clients reach Harbor at — see below |
| `portalName` / `registryName` / `jobserviceName` | `harbor-portal` / `harbor-registry` / `harbor-jobservice` | the other stages, by Service name |
| `dbHost` / `dbPort` / `dbName` / `dbUser` / `dbSslMode` | `harbor-db-rw` / `5432` / `registry` / `harbor` / `disable` | |
| `redisHost` / `redisPort` | `harbor-cache` / `6379` | core uses Redis DB 0 |
| `registryUser` | `harbor_registry_user` | the basic-auth user core presents to the registry |
| `secretName` | `harbor` | the shared Secret — see below |
| `replicas` / `logLevel` / `env` / `resources` / `labels` / `annotations` / `podLabels` / `podAnnotations` | | |

### `portal`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `harbor-portal` | |
| `image` | `docker.io/goharbor/harbor-portal:v2.15.0` | |
| `replicas` / `resources` / `labels` / `annotations` / `podLabels` / `podAnnotations` | | |

### `registry`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `harbor-registry` | |
| `image` / `controllerImage` | `docker.io/goharbor/registry-photon:v2.15.0` / `docker.io/goharbor/harbor-registryctl:v2.15.0` | the controller runs as a sidecar |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the image data volume |
| `storage` | `null` | a distribution `storage` stanza (s3, azure, gcs, …), passed through verbatim; replaces the volume |
| `redisHost` / `redisPort` | `harbor-cache` / `6379` | the registry uses Redis DB 2 |
| `secretName` | `harbor` | |
| `logLevel` / `resources` / `controllerResources` / `labels` / `annotations` / `podLabels` / `podAnnotations` | | |

### `jobservice`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `harbor-jobservice` | |
| `image` | `docker.io/goharbor/harbor-jobservice:v2.15.2` | |
| `coreName` / `registryName` | `harbor-core` / `harbor-registry` | |
| `jobLogs` | `file` | `file` claims a volume for `/var/log/jobs`; `database` keeps the logs in PostgreSQL and claims none |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the job-log volume |
| `maxJobWorkers` | `10` | jobs running at once in this pod |
| `redisHost` / `redisPort` | `harbor-cache` / `6379` | jobservice uses Redis DB 1 |
| `secretName` / `logLevel` / `env` / `resources` / `labels` / `annotations` / `podLabels` / `podAnnotations` | | |

## Exposure

`core` is the only stage that faces outside. It serves the API, the token
service and every registry path a client uses, and forwards the UI requests it
does not answer itself to the portal Service named by `portalName` — so one
exposure on `core` puts the whole of Harbor on one hostname:

```jsonnet
kurly.list([
  core(externalUrl='https://harbor.example.com')
  + kurly.expose.ownGateway('harbor.example.com', 'istio', tls='harbor-tls'),
  kurly.certificate('harbor-tls', ['harbor.example.com'], 'letsencrypt-prod'),
  portal(),
  registry(),
  jobservice(),
])
```

`externalUrl` must be that same address. A `docker login` follows the token realm
the registry hands back, which core builds from `externalUrl`, so a wrong value
sends clients to a host that does not answer — and does so only at login time,
long after the manifests looked right.

Never expose `registry` itself: clients reach it through core, which mints the
bearer token they present, and the registry's own basic-auth credential is not
theirs to use.

## Database and cache

Harbor needs **PostgreSQL** (a database named `registry` by default) and
**Redis**. The defaults pair with the [cnpg-cluster](../cnpg-cluster/) and
[valkey](../valkey/) workloads — a cluster named `harbor-db` and a Valkey named
`harbor-cache`, with core on Redis DB 0, jobservice on 1 and the registry on 2.

```jsonnet
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';

kurly.list([
  cnpg(name='harbor-db', database='registry', owner='harbor'),
  valkey(name='harbor-cache'),
  core(externalUrl='https://harbor.example.com'),
  portal(),
  registry(),
  jobservice(),
])
```

## Secrets

kurly authors **no Secret**. One consumer-provided Secret carries what the stages
share; `core`, `registry` and `jobservice` all read it.

| Key | Used by | Notes |
|---|---|---|
| `secretKey` | core | **exactly 16 characters** — it encrypts the registry credentials stored in the database, so changing it makes every stored credential unreadable |
| `secret` (`CORE_SECRET`) | core, registry, jobservice | how the components authenticate to each other |
| `JOBSERVICE_SECRET` | core, registry, jobservice | the same, in the other direction |
| `CSRF_KEY` | core | 32 characters |
| `HARBOR_ADMIN_PASSWORD` | core | the initial `admin` password |
| `POSTGRESQL_PASSWORD` | core | matching the CNPG `-app` Secret |
| `REGISTRY_CREDENTIAL_PASSWORD` | core, jobservice | the password behind `registryUser` |
| `REGISTRY_HTTP_SECRET` | registry | signs the upload state a client carries between requests |
| `REGISTRY_HTPASSWD` | registry | the bcrypt htpasswd line for `registryUser` and the password above |
| `tls.key` / `tls.crt` | core | the token service's CA keypair |

Two of those cannot be generated from a length. `REGISTRY_HTPASSWD` is a bcrypt
line that has to match `registryUser` and `REGISTRY_CREDENTIAL_PASSWORD`
(`htpasswd -nbBC10 harbor_registry_user "$password"`), and `tls.key`/`tls.crt` is
a self-signed CA Harbor signs its bearer tokens with
(`openssl req -x509 -newkey rsa:4096 -nodes -keyout tls.key -out tls.crt -days 3650 -subj /CN=harbor-token-ca`).
Keep both stable: a new token CA invalidates every token in flight, and a
mismatched htpasswd line leaves core unable to talk to its own registry.

Fill the Secret with [`kurly.externalSecret`](../../main.libsonnet) from your
secret store, or apply it by hand.

## Persistence and scale

`registry` owns the image data and `jobservice` its job logs, each on one
ReadWriteOnce volume, so both are one replica, recreated (never rolled) to keep
two pods off the volume. Point `registry(storage=…)` at an object store and that
stage becomes stateless and scales out — which is what a registry of any size
wants. `core` and `portal` hold nothing and scale horizontally as they are.

Image scanning is off: Harbor scans through a separate Trivy adapter deployment,
which these stages do not carry, so `WITH_TRIVY` is `false` until one is
registered.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: harbor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-harbor, namespace: harbor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/harbor, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: harbor }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-harbor, namespace: harbor }
spec: { sourceRef: { kind: OCIRepository, name: kurly-harbor } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: harbor-core, namespace: harbor }
spec:
  serviceAccountName: harbor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local core = import 'github.com/metio/kurly/workloads/harbor/core.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(core())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-harbor, importPath: github.com/metio/kurly/workloads/harbor }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: harbor-jobservice, namespace: harbor }
spec:
  serviceAccountName: harbor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local jobservice = import 'github.com/metio/kurly/workloads/harbor/jobservice.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(jobservice())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-harbor, importPath: github.com/metio/kurly/workloads/harbor }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: harbor-portal, namespace: harbor }
spec:
  serviceAccountName: harbor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local portal = import 'github.com/metio/kurly/workloads/harbor/portal.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(portal())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-harbor, importPath: github.com/metio/kurly/workloads/harbor }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: harbor-registry, namespace: harbor }
spec:
  serviceAccountName: harbor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local registry = import 'github.com/metio/kurly/workloads/harbor/registry.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(registry())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-harbor, importPath: github.com/metio/kurly/workloads/harbor }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: harbor, namespace: harbor }
spec:
  serviceAccountName: harbor-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: core
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: harbor-core
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: harbor-core }
    - name: jobservice
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: harbor-jobservice
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: harbor-jobservice }
    - name: portal
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: harbor-portal
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: harbor-portal }
    - name: registry
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: harbor-registry
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: harbor-registry }
```

<!-- END generated: jaas-deploy -->
