#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the redaxo workload: provision the throwaway MariaDB it defaults to,
# mint the Secret it reads, then boot the stage and wait for health. The
# entrypoint installs into an empty document root on the first boot, so the
# database has to be reachable before the pod starts, not merely before it serves.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-redaxo
kurly::namespace "$ns"

kurly::mysql "$ns" redaxo-db redaxo redaxo

kubectl --namespace="$ns" create secret generic redaxo \
  --from-literal="REDAXO_DB_PASSWORD=${KURLY_E2E_PASSWORD}" \
  --from-literal="REDAXO_ADMIN_PASSWORD=${KURLY_E2E_PASSWORD}" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/redaxo/server.libsonnet "$ns"
