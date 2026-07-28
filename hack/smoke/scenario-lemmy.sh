#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the lemmy workload. The backend reads a lemmy.hjson holding the instance's
# identity, its database connection, and the shared pict-rs key — kurly authors
# none, so the smoke supplies the smallest one that lets all three stages (backend,
# pict-rs, UI) come up against the throwaway PostgreSQL.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-lemmy
kurly::namespace "$ns"

kurly::postgres "$ns" lemmy-db-rw lemmy lemmy

pictrs_key="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"

config="$(mktemp)"
trap 'rm -f "$config"' EXIT
cat >"$config" <<HJSON
{
  hostname: "lemmy.example.com"
  bind: "0.0.0.0"
  port: 8536
  tls_enabled: false
  database: {
    host: "lemmy-db-rw"
    port: 5432
    database: "lemmy"
    user: "lemmy"
    password: "${KURLY_E2E_PASSWORD}"
  }
  pictrs: {
    url: "http://lemmy-pictrs:8080/"
    api_key: "${pictrs_key}"
  }
}
HJSON

kubectl --namespace="$ns" create secret generic lemmy \
  --from-file=config.hjson="$config" --dry-run=client --output=yaml | kubectl apply --filename=-

# pict-rs authenticates the backend with the same key the backend's config carries.
kubectl --namespace="$ns" create secret generic lemmy-pictrs \
  --from-literal=PICTRS__SERVER__API_KEY="${pictrs_key}" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/lemmy/pictrs.libsonnet "$ns"
kurly::boot workloads/lemmy/backend.libsonnet "$ns"
kurly::boot workloads/lemmy/ui.libsonnet "$ns"
