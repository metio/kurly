#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the budget-board workload: a throwaway PostgreSQL at the service name the
# server defaults to, the one-key Secret it reads, then both stages — the API first,
# because the client's nginx resolves its upstream at start.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-budget-board
kurly::namespace "$ns"

kurly::postgres "$ns" budget-board-db-rw budgetboard budgetboard

kubectl --namespace="$ns" create secret generic budget-board \
  --from-literal=POSTGRES_PASSWORD="$KURLY_E2E_PASSWORD" \
  --dry-run=client --output=yaml | kubectl apply --namespace="$ns" --filename=-

kurly::boot workloads/budget-board/server.libsonnet "$ns"
kurly::boot workloads/budget-board/client.libsonnet "$ns"
