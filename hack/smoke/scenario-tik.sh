#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the tik workload: render its backend stage as a consumer would, apply
# it, and wait for the board to become Available (its readiness probe is
# GET /tickets.edn, so a green rollout proves the board serves). No operator.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-tik
kurly::namespace "$ns"

echo "== apply the tik backend (PVC + ConfigMap + Deployment + Service) =="
# kind-in-CI cannot nest user namespaces, so relax that one knob for the smoke;
# the read-only root filesystem, dropped caps, seccomp, mounts, pinned uid, and
# Recreate strategy are all still exercised.
kurly::render workloads/tik/backend.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the tik board to become Available =="
if ! kubectl --namespace="$ns" rollout status deployment/tik --timeout=300s; then
  kurly::diagnose "$ns"
  exit 1
fi
echo "tik is Ready on a live cluster"
