#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the drop workload: provision a throwaway postgres at the service name
# the stage defaults to, mint the Secret carrying DATABASE_URL, then boot the
# stage on a live cluster and wait for it to become healthy. EXTERNAL_URL is the
# address the desktop client is handed, so the in-cluster Service name stands in
# for it here rather than being baked into the stage.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-drop
kurly::namespace "$ns"

kurly::postgres "$ns" drop-db-rw drop drop

kubectl --namespace="$ns" create secret generic drop \
  --from-literal=DATABASE_URL="postgresql://drop:${KURLY_E2E_PASSWORD}@drop-db-rw:5432/drop?sslmode=disable" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/drop/server.libsonnet "$ns" "+ k.env({ EXTERNAL_URL: 'http://drop:3000' })"
