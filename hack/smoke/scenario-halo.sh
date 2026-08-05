#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the halo workload: mint the Secret carrying the superadmin password,
# then boot the stage on a live kind cluster and wait for it to become healthy.
# No external dependency — the default database is the embedded H2 file inside
# the work directory.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-halo
kurly::namespace "$ns"

kubectl --namespace="$ns" create secret generic halo \
  --from-literal=HALO_SECURITY_INITIALIZER_SUPERADMINPASSWORD="$KURLY_E2E_PASSWORD" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/halo/server.libsonnet "$ns"
