---
title: Upgrading
description: What each kurly release asks an operator to do before the next render lands.
---

Most releases ask nothing: a workload picks up a new library with its own next
render. This page carries the ones that need a decision first.

kurly cuts a release on every push, with a calendar version that carries the
time of day (`library-2026.8.3141650`), so an entry is dated rather than
numbered and applies from the first release of that day onward.

## 2026-08-03 — service mesh support

`kurly.mesh.istio()` is new, and running a workload under it changes what your
cluster admits.

Istio's default install programs each pod's traffic redirection from an
`istio-init` container that runs **as root with `NET_ADMIN` and `NET_RAW`, and a
writable root filesystem**. That container lands in every meshed pod, and it is
not one kurly renders — the injector adds it at admission, after the manifest is
written. Measured against the [bollwerk](https://github.com/metio/bollwerk)
policies, it breaks three of them that the same workload passes when unmeshed.
If you enforce a hardened admission baseline, meshed pods will be rejected.

**Install Istio's CNI plugin, and tell istiod it is there.** The plugin moves
that work to a node agent, so the injected pod gets an unprivileged
`istio-validation` container instead and the three violations go away:

```shell
helm upgrade --install istio-cni istio/cni --namespace istio-system
helm upgrade istiod istio/istiod --namespace istio-system \
  --reuse-values --set pilot.cni.enabled=true
```

The second command is not optional. Installing the chart alone leaves istiod
still injecting `istio-init`, and nothing reports that it is doing so.

The privilege is relocated rather than removed: the CNI node agent is itself
privileged. That is a better place for it — one component you exempt
deliberately, the way a CSI driver is exempted, rather than a relaxation in
every tenant's pod — but it needs an exemption, and it is yours to grant.

**Point the proxy at a registry you allow.** Istio publishes from
`registry.istio.io/release`, which an allow-list cluster refuses and an
air-gapped one cannot reach. Name the image on the workload and `kurly.mirror`
will follow it onto your private registry along with everything else:

```jsonnet
app + kurly.mesh.istio(proxyImage='ghcr.io/acme/mesh/proxyv2:1.30.3')
```

One annotation covers both injected containers — istiod reads it for the proxy
and for `istio-init` alike.

`hack/smoke/deep/mesh-bsi.sh` in the repository is the measurement behind all of
this. Re-run it against your own Istio version rather than trusting these
numbers.
