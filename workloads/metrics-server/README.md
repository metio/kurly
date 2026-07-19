<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# metrics-server

The [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server):
it scrapes CPU/memory usage from every node's kubelet and serves it through the
aggregated `metrics.k8s.io` API — what `kubectl top` and **Horizontal Pod
Autoscalers** read. Essential on any cluster that doesn't already ship it.

A plain composable `kurly.http` workload, but one that registers an `APIService`
and needs the aggregation RBAC, so it carries a ServiceAccount, ClusterRoles and
bindings, the kube-system auth-reader RoleBinding, and the APIService alongside
its Deployment and Service.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local metricsServer = import 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet';

kurly.list(metricsServer(kubeletInsecureTLS=true))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `metrics-server` | |
| `namespace` | `kube-system` | **must match where you deploy** — see below |
| `image` | `registry.k8s.io/metrics-server/metrics-server:v0.8.1` | |
| `replicas` | `1` | |
| `kubeletInsecureTLS` | `false` | skip verifying the kubelet serving cert — see below |
| `metricResolution` | `15s` | |
| `resources` / `labels` / `annotations` | | |

## `kubeletInsecureTLS`

metrics-server connects to each kubelet over TLS and, by default, verifies the
kubelet's serving certificate against the cluster CA. Many clusters — **kind**,
kubeadm without serving-cert rotation, various on-prem setups — give the kubelets
a **self-signed** serving cert, and the scrape then fails the handshake with no
metrics. Set `kubeletInsecureTLS=true` there. On a cluster that rotates
kubelet serving certs properly, leave it off.

## Why `namespace` is required

The `APIService` and the cluster RBAC name the ServiceAccount by namespace, and a
cluster-scoped object can't be namespace-stamped by the consumer later — so the
namespace has to be known at render and must match where you deploy. The
`extension-apiserver-authentication-reader` RoleBinding is always in `kube-system`
(that's where the ConfigMap it reads lives), regardless of where metrics-server
itself runs.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-metrics-server, namespace: kube-system }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/metrics-server
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-metrics-server, namespace: kube-system }
spec: { sourceRef: { kind: OCIRepository, name: kurly-metrics-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: metrics-server, namespace: kube-system }
spec:
  serviceAccountName: metrics-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local metricsServer = import 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet';
      function(insecure=false) kurly.list(metricsServer(kubeletInsecureTLS=insecure))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,                importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-metrics-server, importPath: github.com/metio/kurly/workloads/metrics-server }
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: metrics-server, namespace: kube-system }
spec:
  serviceAccountName: metrics-server-deployer
  stages:
    - name: metrics-server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: metrics-server
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: Deployment
            name: metrics-server
```
