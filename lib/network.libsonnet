// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// network: allow-list network policy, composed onto a workload with `+`. Like
// expose, it is a separate axis with one recipe per implementation — pick the
// variant matching the cluster's CNI:
//
//   Kubernetes NetworkPolicy:   kubernetes(allowFrom, allowTo)
//   Calico (projectcalico/v3):  calico(allowFrom, allowTo)
//   Cilium (cilium.io/v2):      cilium(allowFrom, allowTo)
//
// Every variant emits ONE policy named after the workload (the same name as its
// Deployment), selecting the workload's own pods, and carrying only the allows
// you list — a Kubernetes NetworkPolicy that selects a pod already denies every
// peer it does not name, so an allow-list is deny-by-default for that pod
// without a separate rule. All three join the `networkPolicy` exclusion group,
// so composing two variants fails the render — a workload firewalls one way.
//
// The rules are written ONCE in a small neutral vocabulary (allowFrom/allowTo
// entries of { pods, namespaces | namespace, cidr, ports }) and each variant
// TRANSLATES it into its native kind (the translation lives in
// networkpolicy.libsonnet, called by the base). Anything the vocabulary does not
// cover (Calico order/tiers/serviceaccount selectors, Cilium L7/DNS/entities)
// passes through VERBATIM via each variant's escape hatch — kurly does not model
// the full CNI schemas, which would drift, the same restraint migrations() takes
// with stageset Actions.
//
// The cluster-wide or namespace-wide default-DENY baseline is deliberately NOT
// baked into a workload's policy: an operator picks it once for the whole
// cluster (a global Calico policy) or per namespace, so it is offered as the
// standalone denyAll.* generators below rather than forced onto every workload.

// A neutral config.networkPolicy slot, so every variant recipe writes the same
// shape and the base's computed field dispatches on `variant`.
local slot(variant, allowFrom, allowTo, ingress, egress, policyTypes, extraSpec) = {
  variant: variant,
  allowFrom: allowFrom,
  allowTo: allowTo,
  ingress: ingress,
  egress: egress,
  policyTypes: policyTypes,
  extraSpec: extraSpec,
};

// A variant recipe claims the shared `networkPolicy` exclusion group, so no two
// can coexist on one workload, and asserts it composes onto a real workload.
local policy(name) = {
  assert std.objectHasAll(self, 'config') :
         'kurly.network recipes firewall a workload — compose them onto a kurly kind (http, worker, …)',
  config+:: { exclusive+: { networkPolicy+: [name] } },
};

{
  // kubernetes emits a networking.k8s.io/v1 NetworkPolicy. `ingress`/`egress`
  // take verbatim native rules for anything the neutral vocabulary does not
  // cover; `policyTypes` forces the denied directions (a null lets Kubernetes
  // infer them from the rules present).
  kubernetes(allowFrom=[], allowTo=[], ingress=[], egress=[], policyTypes=null):: policy('kubernetes') {
    config+:: { networkPolicy: slot('kubernetes', allowFrom, allowTo, ingress, egress, policyTypes, {}) },
  },

  // calico emits a projectcalico.org/v3 NetworkPolicy. `extraSpec` passes any
  // Calico-only spec fields through verbatim (order, serviceAccountSelector, a
  // Notdestination, …).
  calico(allowFrom=[], allowTo=[], extraSpec={}):: policy('calico') {
    config+:: { networkPolicy: slot('calico', allowFrom, allowTo, [], [], null, extraSpec) },
  },

  // cilium emits a cilium.io/v2 CiliumNetworkPolicy. `extraSpec` passes any
  // Cilium-only spec fields through verbatim (an L7 rules block on a toPorts,
  // toFQDNs, ingressDeny, …).
  cilium(allowFrom=[], allowTo=[], extraSpec={}):: policy('cilium') {
    config+:: { networkPolicy: slot('cilium', allowFrom, allowTo, [], [], null, extraSpec) },
  },

  // Standalone default-DENY policies — the baseline an allow-list workload
  // policy assumes but does not carry. Not composed onto a workload; place one
  // into a stage's manifest set with kurly.list so the cluster (or a
  // namespace) denies every peer no allow-list opens:
  //
  //   kurly.list([ kurly.network.denyAll.calico(global=true) ])
  //
  // Each selects EVERY pod (or every pod cluster-wide with global=true) and
  // names no allows. `extraSpec` passes through the exceptions a real baseline
  // keeps (a Calico order, an allow for kube-dns) verbatim.
  denyAll:: {
    // A per-namespace default-deny: selecting all pods with both policyTypes and
    // no rules denies every direction.
    kubernetes(name='default-deny', extraSpec={}):: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: { name: name, labels: { 'app.kubernetes.io/managed-by': 'kurly' } },
      spec: { podSelector: {}, policyTypes: ['Ingress', 'Egress'] } + extraSpec,
    },

    // global=true emits a cluster-wide GlobalNetworkPolicy (selector all()),
    // otherwise a namespaced NetworkPolicy (selector all() within the namespace).
    calico(name='default-deny', global=false, extraSpec={}):: {
      apiVersion: 'projectcalico.org/v3',
      kind: (if global then 'GlobalNetworkPolicy' else 'NetworkPolicy'),
      metadata: { name: name, labels: { 'app.kubernetes.io/managed-by': 'kurly' } },
      spec: { selector: 'all()', types: ['Ingress', 'Egress'] } + extraSpec,
    },

    // global=true emits a CiliumClusterwideNetworkPolicy, otherwise a namespaced
    // CiliumNetworkPolicy; an empty endpointSelector selects every endpoint and
    // enableDefaultDeny turns both directions off.
    cilium(name='default-deny', global=false, extraSpec={}):: {
      apiVersion: 'cilium.io/v2',
      kind: (if global then 'CiliumClusterwideNetworkPolicy' else 'CiliumNetworkPolicy'),
      metadata: { name: name, labels: { 'app.kubernetes.io/managed-by': 'kurly' } },
      spec: { endpointSelector: {}, enableDefaultDeny: { ingress: true, egress: true } } + extraSpec,
    },
  },
}
