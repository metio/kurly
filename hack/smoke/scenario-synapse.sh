#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Hand-written: the server name is a PARAMETER (it is baked into every id the server
# mints, so it cannot be a composed environment override) and the first-run generate
# step needs it, so the stage is rendered with it set.
# e2e for the synapse workload: provision its declared dependencies (a throwaway
# postgres/valkey at the service names it defaults to), mint the Secret it reads
# from the catalog secretKeys, then boot every stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-synapse
kurly::namespace "$ns"

kurly::postgres "$ns" synapse-db-rw synapse synapse

kurly::secret "$ns" synapse workloads/synapse/server.libsonnet
echo "== boot workloads/synapse/server.libsonnet in ${ns} =="
jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; \
  k.list((import 'workloads/synapse/server.libsonnet')(serverName='synapse.example.com') + k.hostUsers())" \
  | kubectl apply --namespace="$ns" --filename=-
kurly::await_ready "$ns" deployment/synapse \
  || { echo "::error::workloads/synapse/server.libsonnet: never became Ready"; kurly::diagnose "$ns"; exit 1; }
echo "ok: workloads/synapse/server.libsonnet is healthy on a live cluster" "+ k.env({ SYNAPSE_SERVER_NAME: 'synapse.example.com', SYNAPSE_REPORT_STATS: 'no' })"
