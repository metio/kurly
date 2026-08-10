#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the spegel workload. Spegel is a peer-to-peer image mirror that runs as a
# DaemonSet talking to the node's containerd socket, so it authors plain manifests
# rather than a composable base — kurly's features (hostUsers among them) do not
# apply, and it is rendered as-is.
#
# It needs the node's containerd socket and host networking, which kind provides;
# a Ready pod is the mirror registering itself with containerd.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# TWO NODES OR NOTHING. Spegel is a peer-to-peer mirror: /readyz — which gates
# both the startup and readiness probes — reports ready only once the P2P routing
# table holds a peer, and the peers are found by resolving the headless bootstrap
# Service. On a single-node cluster that Service resolves to this pod alone, the
# table stays empty, and the DaemonSet never becomes Ready while the log repeats
# "routing table is empty after bootstrapping". Nothing about the workload is
# wrong there, so the run says so instead of failing it as a defect — measured
# 2026-08-10: identical manifests fail on one node and are healthy on two.
nodes="$(kubectl get nodes --no-headers 2>/dev/null | grep -c .)"
if [ "${nodes:-0}" -lt 2 ]; then
  echo "skip: spegel needs a peer to bootstrap against and this cluster has ${nodes:-0} node(s)."
  echo "      Recreate it with a worker before asserting anything about spegel:"
  echo "        cat > /tmp/kind-2node.yaml <<'YAML'"
  echo "        kind: Cluster"
  echo "        apiVersion: kind.x-k8s.io/v1alpha4"
  echo "        nodes: [{ role: control-plane }, { role: worker }]"
  echo "        YAML"
  echo "        KUBE_CLUSTER_CPUS=4 KUBE_CLUSTER_MEMORY=7G kube-cluster up <name> -- --config /tmp/kind-2node.yaml"
  echo "      (halved, because the cgroup budget applies per node container)"
  exit 0
fi
kurly::vendor

# The manifests state their own namespace, the way a cluster add-on does.
ns=spegel
kurly::namespace "$ns"

echo "== boot workloads/spegel/mirror.libsonnet in ${ns} =="
kurly::render workloads/spegel/mirror.libsonnet | kubectl apply --filename=-

kurly::await_ready "$ns" daemonset/spegel \
  || { echo "::error::workloads/spegel/mirror.libsonnet: daemonset/spegel never became Ready"; kurly::diagnose "$ns"; exit 1; }
echo "ok: workloads/spegel/mirror.libsonnet is healthy on a live cluster"
