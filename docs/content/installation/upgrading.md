---
title: Upgrading
description: What each kurly release asks an operator to do before the next render lands.
---

Most releases ask nothing: a workload picks up a new library with its own next
render. This page carries the ones that need a decision first.

kurly cuts a release on every push, with a calendar version that carries the
time of day (`library-2026.8.3141650`), so an entry is dated rather than
numbered and applies from the first release of that day onward.

## 2026-08-04 — `kurly.mesh.strictNamespace()` moved

The namespace-wide mTLS floor is now named for the mesh it belongs to, because
the axis has more than one and the object it emits is Istio's:

```jsonnet
kurly.list([app, kurly.mesh.strictNamespace.istio()])   // was strictNamespace()
```

Nothing else changes; the object it returns is the same. A render calling the
old name fails outright rather than silently emitting nothing.

Linkerd has no member there and will not get one: its floor is an annotation on
the Namespace object or a control-plane setting, and kurly renders neither.

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

The registry half applies to Linkerd too — it publishes from `cr.l5d.io` — and
`kurly.mesh.linkerd(proxyImage=…)` takes the same treatment. Its injected proxy
has not been measured against the policies; that is a gap, not a clean bill.

`kurly.mesh.linkerd()` injects reliably, but **its inbound policy has not been
shown to refuse anything** — see the mesh section on the front page. Use it for
injection; do not count it as encryption in transit yet.

Measured the same way, Linkerd's injected containers break three policies rather
than Istio's four: `disallow-unwanted-capabilities`, `require-request-limits` and
`restrict-image-registries`. They stay non-root with a read-only root filesystem,
which Istio's `istio-init` does not. Whether Linkerd's CNI plugin clears the
capability line is unmeasured — the injected pod kept `linkerd-init` in both
attempts, so there is no CNI figure to quote.
