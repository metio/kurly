// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The renderer behind the kurly.network axis: it turns a workload's neutral
// allow-list (the config.networkPolicy slot the kurly.network recipes populate)
// into the manifest for the chosen CNI variant, unioning in the requiredEgress a
// sidecar declared. base.core calls render(); the public recipes live in
// network.libsonnet. This is deliberately NOT a catalog axis — it holds no user
// callables, only the translation the base needs.
//
// The neutral peer vocabulary an allowFrom/allowTo entry uses:
//   pods       — a label map selecting pods (matchLabels)
//   namespaces — a label map selecting namespaces
//   namespace  — a namespace NAME, sugar for namespaces via the well-known
//                `kubernetes.io/metadata.name` label
//   cidr       — an IP block, a string or a list of strings
//   ports      — a list of port numbers or { port, protocol } (protocol
//                defaults to TCP); applies to the rule this peer produces

local isSet(v) = v != null && v != {} && v != [];
local get(o, f) = std.get(o, f, null);

// A cidr field may be a single string or a list — normalize to a list.
local cidrList(peer) =
  local c = get(peer, 'cidr');
  if c == null then [] else if std.isArray(c) then c else [c];

// Namespace labels: an explicit label map, plus the well-known name label when a
// namespace NAME is given.
local nsLabels(peer) =
  (if isSet(get(peer, 'namespaces')) then peer.namespaces else {})
  + (if get(peer, 'namespace') != null then { 'kubernetes.io/metadata.name': peer.namespace } else {});

// Ports normalized to [{ protocol, port }]; a bare number means TCP.
local portList(peer) =
  local ps = if get(peer, 'ports') == null then [] else peer.ports;
  [
    if std.isObject(p) then { protocol: std.get(p, 'protocol', 'TCP'), port: p.port }
    else { protocol: 'TCP', port: p }
    for p in ps
  ];

// Ports grouped by protocol, for the CNIs that carry a single protocol per rule.
local portsByProtocol(peer) =
  local ports = portList(peer);
  local protocols = std.set([p.protocol for p in ports]);
  [
    { protocol: proto, ports: [p.port for p in ports if p.protocol == proto] }
    for proto in protocols
  ];

// --- Kubernetes NetworkPolicy (networking.k8s.io/v1) ------------------------
// A neutral peer -> the `from`/`to` blocks of one Kubernetes rule. A selector
// block (pods AND/OR namespaces) and one ipBlock per cidr sit side by side, so
// a peer naming both a selector and a cidr allows either.
local k8sBlocks(peer) =
  local selector =
    (if isSet(get(peer, 'pods')) then { podSelector: { matchLabels: peer.pods } } else {})
    + (if nsLabels(peer) != {} then { namespaceSelector: { matchLabels: nsLabels(peer) } } else {});
  (if selector != {} then [selector] else [])
  + [{ ipBlock: { cidr: c } } for c in cidrList(peer)];

local k8sRule(dir, peer) =
  local blocks = k8sBlocks(peer);
  local ports = portList(peer);
  (if blocks == [] then {} else { [dir]: blocks })
  + (if ports == [] then {} else { ports: ports });

local kubernetesManifest(name, np, selectorLabels, labels, requiredEgress) =
  local ingress = [k8sRule('from', p) for p in np.allowFrom] + np.ingress;
  // requiredEgress is already Kubernetes-shaped (a sidecar's apiserver allow),
  // so it unions straight into the egress list.
  local egress = [k8sRule('to', p) for p in np.allowTo] + np.egress + requiredEgress;
  // A null policyTypes lets Kubernetes infer from the fields present. When the
  // consumer pinned policyTypes and a sidecar's requiredEgress then adds egress,
  // Egress must join or the required rule never takes effect.
  local policyTypes =
    if np.policyTypes != null && requiredEgress != [] && !std.member(np.policyTypes, 'Egress')
    then np.policyTypes + ['Egress'] else np.policyTypes;
  std.prune({
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: { name: name, labels: labels },
    spec: {
      podSelector: { matchLabels: selectorLabels },
      policyTypes: policyTypes,
      ingress: (if ingress == [] then null else ingress),
      egress: (if egress == [] then null else egress),
    },
  });

// --- Calico NetworkPolicy (projectcalico.org/v3) ----------------------------
// v3 is the aggregated, user-facing API; the crd.projectcalico.org/v1 storage
// CRDs are never emitted. Calico selects with a label-expression string, not
// matchLabels.
local calicoSelector(labelMap) =
  if labelMap == null || labelMap == {} then null
  else std.join(' && ', ["%s == '%s'" % [key, labelMap[key]] for key in std.objectFields(labelMap)]);

local calicoNsSelector(peer) =
  if isSet(get(peer, 'namespaces')) then calicoSelector(peer.namespaces)
  else if get(peer, 'namespace') != null then "projectcalico.org/name == '%s'" % peer.namespace
  else null;

// The endpoint half of a Calico rule (who the selected pod may talk to). Ports
// always sit on the destination (the port reached on the target), so a rule is
// split per protocol.
local calicoEndpoint(peer) = std.prune({
  selector: calicoSelector(get(peer, 'pods')),
  namespaceSelector: calicoNsSelector(peer),
  nets: (if cidrList(peer) == [] then null else cidrList(peer)),
});

// dir 'source' for ingress (who connects), 'destination' for egress (who is
// reached). Destination ports name the L4 port in both directions.
local calicoRules(dir, peer) =
  local endpoint = calicoEndpoint(peer);
  local groups = portsByProtocol(peer);
  if groups == [] then
    [{ action: 'Allow' } + (if endpoint == {} then {} else { [dir]: endpoint })]
  else [
    { action: 'Allow', protocol: g.protocol }
    + (if endpoint == {} then {} else { [dir]: endpoint })
    + { destination+: { ports: g.ports } }
    for g in groups
  ];

// requiredEgress (Kubernetes-shaped, allow to anywhere on some ports) rendered
// as Calico egress — one Allow per protocol, no destination selector.
local calicoRequiredEgress(requiredEgress) = std.flattenArrays([
  [
    { action: 'Allow', protocol: g.protocol, destination: { ports: g.ports } }
    for g in portsByProtocol(rule)
  ]
  for rule in requiredEgress
]);

local calicoManifest(name, np, selectorLabels, labels, requiredEgress) =
  local ingress = std.flattenArrays([calicoRules('source', p) for p in np.allowFrom]);
  local egress = std.flattenArrays([calicoRules('destination', p) for p in np.allowTo])
                 + calicoRequiredEgress(requiredEgress);
  local types =
    (if ingress != [] then ['Ingress'] else [])
    + (if egress != [] then ['Egress'] else []);
  {
    apiVersion: 'projectcalico.org/v3',
    kind: 'NetworkPolicy',
    metadata: { name: name, labels: labels },
    spec: std.prune({
      selector: calicoSelector(selectorLabels),
      types: (if types == [] then null else types),
      ingress: (if ingress == [] then null else ingress),
      egress: (if egress == [] then null else egress),
    }) + np.extraSpec,
  };

// --- Cilium CiliumNetworkPolicy (cilium.io/v2) ------------------------------
// Cilium selects endpoints with matchLabels (like Kubernetes); a namespace is a
// label on the endpoint (k8s:io.kubernetes.pod.namespace).
local ciliumMatchLabels(peer) =
  (if isSet(get(peer, 'pods')) then peer.pods else {})
  + (if get(peer, 'namespace') != null then { 'k8s:io.kubernetes.pod.namespace': peer.namespace } else {})
  + (if isSet(get(peer, 'namespaces')) then peer.namespaces else {});

local ciliumPorts(peer) =
  local ports = portList(peer);
  if ports == [] then {}
  else { toPorts: [{ ports: [{ port: std.toString(p.port), protocol: p.protocol } for p in ports] }] };

// dir 'from' for ingress, 'to' for egress. toPorts names the L4 port on the
// selected endpoint in both directions.
local ciliumRule(dir, peer) =
  local ml = ciliumMatchLabels(peer);
  local cidrs = cidrList(peer);
  (if ml == {} then {} else { [dir + 'Endpoints']: [{ matchLabels: ml }] })
  + (if cidrs == [] then {} else { [dir + 'CIDR']: cidrs })
  + ciliumPorts(peer);

local ciliumRequiredEgress(requiredEgress) = [
  { toEntities: ['all'] } + ciliumPorts(rule)
  for rule in requiredEgress
];

local ciliumManifest(name, np, selectorLabels, labels, requiredEgress) =
  local ingress = [ciliumRule('from', p) for p in np.allowFrom];
  local egress = [ciliumRule('to', p) for p in np.allowTo] + ciliumRequiredEgress(requiredEgress);
  {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: { name: name, labels: labels },
    spec: std.prune({
      endpointSelector: { matchLabels: selectorLabels },
      ingress: (if ingress == [] then null else ingress),
      egress: (if egress == [] then null else egress),
    }) + np.extraSpec,
  };

{
  // render turns a populated config.networkPolicy slot into the manifest for its
  // variant, unioning the sidecar requiredEgress the base collected.
  render(name, np, selectorLabels, labels, requiredEgress)::
    if np.variant == 'calico' then calicoManifest(name, np, selectorLabels, labels, requiredEgress)
    else if np.variant == 'cilium' then ciliumManifest(name, np, selectorLabels, labels, requiredEgress)
    else kubernetesManifest(name, np, selectorLabels, labels, requiredEgress),
}
