#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the snypy workload: provision the PostgreSQL it defaults to, mint the
# Secret it reads (DATABASE_URL, SECRET_KEY), then boot the stage and wait for
# health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-snypy
kurly::namespace "$ns"

kurly::postgres "$ns" snypy-db-rw snypy snypy

kubectl --namespace="$ns" create secret generic snypy \
  --from-literal=DATABASE_URL="postgresql://snypy:${KURLY_E2E_PASSWORD}@snypy-db-rw:5432/snypy?sslmode=disable" \
  --from-literal=SECRET_KEY="$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c 1-64)" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/snypy/server.libsonnet "$ns" "" ""
