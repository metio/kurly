#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the dex workload. Dex is driven entirely by a config.yaml it reads from a
# Secret (kurly authors none, because a real one carries client and connector
# secrets), so the smoke supplies the smallest config that serves OIDC: PostgreSQL
# storage on the throwaway database, one static client, and the local password
# database. Booting it proves the image, the command, the mount paths, and the
# health endpoint still line up.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-dex
kurly::namespace "$ns"

kurly::postgres "$ns" dex-db-rw dex dex

config="$(mktemp)"
trap 'rm -f "$config"' EXIT
cat >"$config" <<YAML
issuer: http://dex:5556
storage:
  type: postgres
  config:
    host: dex-db-rw
    port: 5432
    database: dex
    user: dex
    password: ${KURLY_E2E_PASSWORD}
    ssl:
      mode: disable
web:
  http: 0.0.0.0:5556
staticClients:
  - id: smoke
    name: smoke
    secret: smoke-client-secret
    redirectURIs:
      - http://localhost/callback
enablePasswordDB: true
YAML

kubectl --namespace="$ns" create secret generic dex \
  --from-file=config.yaml="$config" --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/dex/server.libsonnet "$ns"
