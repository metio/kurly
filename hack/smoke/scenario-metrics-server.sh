#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the metrics-server workload. Unlike every other workload this one is a
# cluster add-on: it renders its own namespace (kube-system), the cluster roles it
# binds, and the APIService that registers metrics.k8s.io — so it is applied as
# rendered rather than into a per-workload namespace, and awaited where it lands.
#
# kind already ships a metrics-server, so this replaces it and then waits for the
# rollout, which proves the rendered add-on actually serves the API.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

echo "== boot workloads/metrics-server/server.libsonnet (cluster add-on) =="
# kind's control plane serves its own certificate for an IP the kubelet's serving
# cert does not cover, so the add-on needs the insecure-TLS flag every kind guide
# uses; that is a property of the cluster, not of the workload.
jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; \
  k.list((import 'workloads/metrics-server/server.libsonnet')(kubeletInsecureTLS=true) + k.hostUsers())" \
  | kubectl apply --filename=-

kurly::await_ready kube-system deployment/metrics-server \
  || { echo "::error::metrics-server never became Ready"; kurly::diagnose kube-system; exit 1; }
echo "ok: workloads/metrics-server/server.libsonnet is healthy on a live cluster"
