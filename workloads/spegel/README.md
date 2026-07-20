<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# spegel

[Spegel](https://spegel.dev) — a stateless, cluster-local OCI registry mirror. One pod
per node (a DaemonSet) serves image layers already present in the node's containerd
content store to its peers over a peer-to-peer router, so a pull satisfied by any node
in the cluster never leaves it. An init container writes containerd's registry-mirror
config, so the kubelet pulls through the local Spegel first.

This is genuinely node-level infrastructure, so — like the [database
clusters](../cnpg-cluster/) — it authors its manifests directly rather than composing a
kurly base kind. kurly features do **not** apply to it (composing one fails the render).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local spegel = import 'github.com/metio/kurly/workloads/spegel/mirror.libsonnet';

kurly.list(spegel(namespace='spegel'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `spegel` | |
| `namespace` | `spegel` | **load-bearing** — the bootstrap DNS name embeds it; must match the deploy namespace |
| `image` | `ghcr.io/spegel-org/spegel:v0.7.4` | |
| `containerdSock` | `/run/containerd/containerd.sock` | the node's containerd socket (mounted read-only) |
| `containerdContentPath` | `/var/lib/containerd/io.containerd.content.v1.content` | content store (mounted read-only) |
| `containerdRegistryConfigPath` | `/etc/containerd/certs.d` | where the mirror config is written |
| `containerdNamespace` | `k8s.io` | |
| `registryPort` | `5000` | the mirror's container port |
| `registryHostPort` / `registryNodePort` | `30020` / `30021` | the kubelet reaches the local mirror at both — the hostPort straight to the local pod, the NodePort through kube-proxy; set `registryHostPort=null` where host ports are forbidden |
| `routerPort` / `metricsPort` | `5001` / `9090` | P2P router / metrics |
| `dataDir` | `/var/lib/spegel` | hostPath for persisted routing state (`null` to disable) |
| `resolveTags` / `mirrorResolveRetries` / `mirrorResolveTimeout` | `true` / `3` / `20ms` | mirror resolution tuning |
| `debugWeb` | `false` | serve Spegel's debug web UI on the registry port |
| `clusterDomain` | `cluster.local` | |
| `resources` / `tolerations` / `nodeSelector` / `affinity` / `priorityClassName` | | `nodeSelector` keeps it on Linux nodes; consider `priorityClassName='system-node-critical'` |
| `labels` / `annotations` | | |

## Why the namespace matters

Peers bootstrap the P2P router against the DNS name of the headless
`<name>-bootstrap` Service, whose FQDN embeds the namespace. Deploy Spegel to the
namespace you pass as `namespace`, or the nodes never find each other.

## Local routing

The kubelet must reach its own node's mirror at `http://<node-ip>:<port>`. Both a
**hostPort** (straight to the local pod) and a **NodePort** (through kube-proxy) are
written into containerd's mirror config, so a node always finds its local Spegel even
when kube-proxy topology-aware routing is not in play. Where host ports are forbidden,
set `registryHostPort=null` and the NodePort carries it alone.

## Node access and security

The mirror serves the node's containerd content store, so it runs **as root with
hostPath mounts** (the socket is root-owned) — the restricted Pod Security Standard
cannot admit it. The posture is hardened as far as the job allows: read-only root
filesystem, no privilege escalation, all capabilities dropped, RuntimeDefault seccomp,
and the socket and content store are mounted read-only. Deploy it to a namespace
labelled for privileged node infrastructure.

A relocated containerd socket or content path (k3s, some managed distros) needs the
`containerd*` parameters pointed at the real locations, or the mirror serves nothing.
