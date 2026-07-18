<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# status-responder

A tiny HTTP service that answers **every** request with one fixed status code and
message. Deploy it once, globally, and route protected paths to it from a Gateway
API `HTTPRoute` — the portable way to take a path off the public internet while
the workload behind it stays reachable in-cluster.

## Why this exists

Gateway API has no portable filter that returns a fixed status code. The
empty-`backendRefs` trick the spec says should return 404 is honoured
inconsistently — Envoy Gateway returns 500, and Istio did until recently — so you
cannot rely on it. A real service that always answers the same way is the
dependable substitute: point a route rule at it and that path is sunk.

`ingress-nginx` solves this with configuration-snippet annotations; Gateway API
has no equivalent, so this fills the gap.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local responder = import 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet';

kurly.list(responder(name='forbidden', statusCode=403, message='forbidden'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `forbidden` | also the Service name a route targets |
| `statusCode` | `403` | the status every request receives |
| `message` | `forbidden` | the response body |
| `labels` / `annotations` | `{}` | on metadata and the pod template |

Deploy one responder per status you need — a `forbidden` (403) and a `not-found`
(404), say. Each is a `hashicorp/http-echo` Deployment on port 5678 with the
restricted security posture and a TCP readiness probe (an HTTP probe would fail,
since the responder answers its fixed status on every path).

## Protecting a path

Two pieces on the protected workload's side, one here.

On the workload, compose `kurly.expose.guard` after the exposure recipe to sink
the protected prefixes to the responder's Service:

```jsonnet
kurly.http('etherpad', image)
+ kurly.expose.listenerSet('pad.example.com', 'shared')
+ kurly.expose.guard(['/admin', '/stats'], 'not-found', serviceNamespace='shared-http-services')
```

Gateway API resolves overlapping matches by specificity, so `/admin` wins over the
catch-all `/` for those requests and is answered by the responder — everything
else reaches etherpad. The workload's own Service is untouched, so internal
clients (a `port-forward`, an in-cluster caller) still reach `/admin` directly.

When the responder lives in another namespace, the cross-namespace `backendRef`
needs consent. Grant it here with `kurly.expose.referenceGrant`, naming the
namespaces allowed to route to this Service:

```jsonnet
responder(name='not-found', statusCode=404, message='not found')
+ kurly.expose.referenceGrant(['team-a', 'team-b'])
```

One `ReferenceGrant` lists every granted namespace; add a namespace to the list
rather than deploying another responder.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-status-responder, namespace: shared-http-services }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/status-responder
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-status-responder, namespace: shared-http-services }
spec: { sourceRef: { kind: OCIRepository, name: kurly-status-responder } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: not-found, namespace: shared-http-services }
spec:
  serviceAccountName: responder-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local responder = import 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet';
      function(tenants=[])
        kurly.list(responder(name='not-found', statusCode=404, message='not found')
                   + kurly.expose.referenceGrant(tenants))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,                   importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-status-responder,  importPath: github.com/metio/kurly/workloads/status-responder }
  tlas:
    - name: tenants
      value: [team-a, team-b]
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: not-found, namespace: shared-http-services }
spec:
  serviceAccountName: responder-deployer
  stages:
    - name: not-found
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: not-found
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: Deployment
            name: not-found
```
