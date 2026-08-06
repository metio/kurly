<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# zoraxy

[Zoraxy](https://github.com/tobychui/zoraxy) — an HTTP reverse proxy and
forwarding tool driven entirely from a web management interface rather than a
configuration file. A plain composable `kurly.http` workload keeping its
configuration database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local zoraxy = import 'github.com/metio/kurly/workloads/zoraxy/server.libsonnet';

kurly.list(zoraxy())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `zoraxy` | |
| `image` | `docker.io/zoraxydocker/zoraxy:v3.3.3` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/opt/zoraxy/config` |
| `env` | `PORT=8000`, `DOCKER=false`, `MDNS=false`, `ZEROTIER=false` | merged over, so a key you set wins |
| `resources` / `labels` / `annotations` | | |

## The Service publishes the management interface, not the proxy

The only port declared here is `:8000`, the web management interface. Zoraxy opens
the listeners for the sites it proxies **at runtime**, from what an operator
configures in that interface — `:80` and `:443` out of the box, and whatever else
it is later told to listen on. None of that is known when this manifest is
rendered, so publish the ones you use yourself:

```jsonnet
zoraxy() + kurly.extraPort('proxy', 80) + kurly.extraPort('proxy-tls', 443)
```

The management interface has no authentication until the first account is created
through it, so keep it off the public internet, or put an exposure with
authentication in front of it, before the pod is reachable.

## Why it runs as root with a writable root filesystem

The image's entrypoint runs `update-ca-certificates` before starting anything,
which rewrites `/etc/ssl/certs`. It is run with `check=True`, so on a read-only
root filesystem — or as a user that may not write there — the entrypoint exits `1`
and the pod never starts. Capabilities stay dropped and privilege escalation stays
off.

## Container integration and mDNS are off

The image enables both by default. `DOCKER=true` has Zoraxy look for a Docker
socket a pod does not have, and `MDNS=true` multicasts on a network where nothing
answers. Set them back through `env` if your cluster gives Zoraxy something to
find.

## Persistence

One configuration database — plus the issued certificates and the site definitions
— on a ReadWriteOnce volume, so this is **one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: zoraxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-zoraxy, namespace: zoraxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/zoraxy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: zoraxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-zoraxy, namespace: zoraxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-zoraxy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: zoraxy, namespace: zoraxy }
spec:
  serviceAccountName: zoraxy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/zoraxy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-zoraxy, importPath: github.com/metio/kurly/workloads/zoraxy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: zoraxy, namespace: zoraxy }
spec:
  serviceAccountName: zoraxy-deployer
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
        name: zoraxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: zoraxy }
```

<!-- END generated: jaas-deploy -->
