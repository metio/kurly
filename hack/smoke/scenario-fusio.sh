#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the fusio workload: provision a throwaway MariaDB at the service name its
# DSN points at, mint the Secret it reads, then boot the stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-fusio
kurly::namespace "$ns"

kurly::mysql "$ns" fusio-db fusio fusio

kubectl create secret generic fusio --namespace="$ns" \
  --from-literal=FUSIO_CONNECTION="mysql://fusio:${KURLY_E2E_PASSWORD}@fusio-db:3306/fusio" \
  --from-literal=FUSIO_PROJECT_KEY="0123456789abcdef0123456789abcdef" \
  --from-literal=FUSIO_BACKEND_PW="${KURLY_E2E_PASSWORD}" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/fusio/server.libsonnet "$ns"
