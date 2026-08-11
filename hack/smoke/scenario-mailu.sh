#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the mailu workload. Its six stages share ONE volume — the mail store,
# the TLS material, and the filter state all live on it — which the workload
# deliberately does not create, because the claim is the operator's decision
# (ReadWriteMany on a real cluster, one node here). The scenario creates it, then
# provisions the cache and boots every stage.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns="$(kurly::namespace_unique kurly-mailu)"
kurly::namespace "$ns"

# Mailu addresses Redis without credentials, so the cache is left open.
kurly::cache "$ns" mailu-cache ""

# The shared claim every stage mounts, and the DNSSEC-validating resolver.
kurly::prereq mailu "$ns"

# Every stage is told where that resolver is. Mailu takes an ADDRESS, not a name,
# so the Service's ClusterIP is read back rather than assumed.
resolver="$(kubectl --namespace="$ns" get service mailu-resolver -o jsonpath='{.spec.clusterIP}')"
echo "== mailu resolver at ${resolver} =="
# RESOLVER_ADDRESS configures nginx; it is NOT what the admin validates. That
# check reads /etc/resolv.conf, so the POD has to resolve through unbound —
# otherwise it keeps testing the cluster's DNS, finds no DNSSEC, and terminates
# itself however the parameter is set. dnsPolicy None replaces the resolver
# outright, which is why the resolver above also answers cluster.local.
params="resolverAddress='${resolver}'"
compose="+ k.dns('None', { nameservers: ['${resolver}'], searches: ['${ns}.svc.cluster.local', 'svc.cluster.local', 'cluster.local'], options: [{ name: 'ndots', value: '5' }] })"

kurly::secret "$ns" mailu workloads/mailu/admin.libsonnet
kurly::boot workloads/mailu/admin.libsonnet "$ns" "$compose" "$params"
kurly::secret "$ns" mailu workloads/mailu/antispam.libsonnet
kurly::boot workloads/mailu/antispam.libsonnet "$ns" "$compose" "$params"
kurly::secret "$ns" mailu workloads/mailu/front.libsonnet
kurly::boot workloads/mailu/front.libsonnet "$ns" "$compose" "$params"
kurly::secret "$ns" mailu workloads/mailu/imap.libsonnet
kurly::boot workloads/mailu/imap.libsonnet "$ns" "$compose" "$params"
kurly::secret "$ns" mailu workloads/mailu/smtp.libsonnet
kurly::boot workloads/mailu/smtp.libsonnet "$ns" "$compose" "$params"
kurly::secret "$ns" mailu workloads/mailu/webmail.libsonnet
kurly::boot workloads/mailu/webmail.libsonnet "$ns" "$compose" "$params"
