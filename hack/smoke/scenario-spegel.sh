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
kurly::vendor

# The manifests state their own namespace, the way a cluster add-on does.
ns=spegel
kurly::namespace "$ns"

echo "== boot workloads/spegel/mirror.libsonnet in ${ns} =="
kurly::render workloads/spegel/mirror.libsonnet | kubectl apply --filename=-

kurly::await_ready "$ns" daemonset/spegel \
  || { echo "::error::workloads/spegel/mirror.libsonnet: daemonset/spegel never became Ready"; kurly::diagnose "$ns"; exit 1; }
echo "ok: workloads/spegel/mirror.libsonnet is healthy on a live cluster"
