// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An allow-list firewall: the API accepts traffic only from the ingress
// namespace's gateway pods and reaches out only to its database. kurly.network
// is a separate axis with one recipe per CNI — swap kubernetes() for calico()
// or cilium() to emit the same intent as a projectcalico.org/v3 NetworkPolicy or
// a cilium.io/v2 CiliumNetworkPolicy. The NetworkPolicy is named after the
// workload and selects its own pods, so an allow-list is deny-by-default for the
// API without any extra rule.
local kurly = import '../main.libsonnet';

kurly.listOf([
  kurly.list(
    kurly.http('users', 'ghcr.io/example/users-api:2.4.1')
    + kurly.port(3000)
    + kurly.network.kubernetes(
      allowFrom=[
        { pods: { 'app.kubernetes.io/name': 'gateway' }, namespace: 'ingress', ports: [3000] },
      ],
      allowTo=[
        { pods: { 'app.kubernetes.io/name': 'postgres' }, namespace: 'databases', ports: [5432] },
        // DNS to the cluster resolver, so name resolution survives the deny-all.
        { namespace: 'kube-system', ports: [{ port: 53, protocol: 'UDP' }] },
      ],
    )
  ),
  // The namespace-wide baseline the allow-list assumes: everything not opened by
  // a workload's own policy is denied. An operator relying on a cluster-wide
  // Calico policy drops this and applies kurly.network.denyAll.calico(global=true)
  // once instead.
  kurly.network.denyAll.kubernetes(),
])
