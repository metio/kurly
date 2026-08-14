<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cloudflare-tunnel-ingress-controller

[Cloudflare Tunnel Ingress Controller](https://github.com/STRRL/cloudflare-tunnel-ingress-controller)
— publishes Ingress objects through a Cloudflare Tunnel rather than a load balancer. It
watches Ingresses of its class, programs the tunnel's routes and the matching DNS
records, and the tunnel dials **out** to Cloudflare, so nothing in the cluster has to be
reachable from the internet and no public address has to be bought.

A composable `kurly.worker` workload: it serves no traffic of its own, so it renders no
Service. It creates no CustomResource and owns none — the interface is the standard
Ingress carrying this controller's class.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local controller = import 'github.com/metio/kurly/workloads/cloudflare-tunnel-ingress-controller/controller.libsonnet';

kurly.list(controller(
  namespace='cloudflare-tunnel',
  accountId='023e105f4ecef8ad9ca31a8372d0c353',
  tunnelName='kubernetes',
))
```

## The account id is not optional

`accountId` defaults to empty, which omits the flag and leaves a controller that exits on
its first reconcile. That is deliberate: the account is a fact about the deployment and
there is no value worth guessing. `namespace` must likewise be the namespace it is
deployed into, because the ClusterRoleBinding's subject needs one.

## The API token can repoint your DNS

The token needs Zone:Read, DNS:Edit and Cloudflare Tunnel:Edit on the account, so
whatever holds it can change where the zone points. It comes from a Secret as
`CLOUDFLARE_API_TOKEN` and reaches the flag through `$(CLOUDFLARE_API_TOKEN)`, which
Kubernetes expands from the container's own environment — the token is never written into
a manifest. kurly authors no Secret: the token is issued in your Cloudflare account
against zones you own, and nothing can generate it for you.

## What the cluster-wide grant is for

An Ingress is a namespaced object that exists in every namespace, so watching them and
writing their status is a ClusterRole. Read-only on Services and Endpoints, and nothing
else.

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
metadata: { name: kurly, namespace: cloudflare-tunnel-ingress-controller }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cloudflare-tunnel-ingress-controller, namespace: cloudflare-tunnel-ingress-controller }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cloudflare-tunnel-ingress-controller, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cloudflare-tunnel-ingress-controller }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cloudflare-tunnel-ingress-controller, namespace: cloudflare-tunnel-ingress-controller }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cloudflare-tunnel-ingress-controller } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cloudflare-tunnel-ingress-controller, namespace: cloudflare-tunnel-ingress-controller }
spec:
  serviceAccountName: cloudflare-tunnel-ingress-controller-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local controller = import 'github.com/metio/kurly/workloads/cloudflare-tunnel-ingress-controller/controller.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(controller())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cloudflare-tunnel-ingress-controller, importPath: github.com/metio/kurly/workloads/cloudflare-tunnel-ingress-controller }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cloudflare-tunnel-ingress-controller, namespace: cloudflare-tunnel-ingress-controller }
spec:
  serviceAccountName: cloudflare-tunnel-ingress-controller-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: controller
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cloudflare-tunnel-ingress-controller
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cloudflare-tunnel-ingress-controller }
```

<!-- END generated: jaas-deploy -->
