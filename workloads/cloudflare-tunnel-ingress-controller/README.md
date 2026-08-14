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
