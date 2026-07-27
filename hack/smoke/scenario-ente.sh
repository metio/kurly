#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the ente workload. Museum (the server) reads its whole configuration —
# database connection, S3 buckets, JWT secrets — from a credentials.yaml it takes
# from a Secret, which kurly deliberately authors none of. The smoke supplies the
# smallest one that lets it start against the throwaway PostgreSQL, so the boot
# proves the image, the mount path, and the health endpoint still line up.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-ente
kurly::namespace "$ns"

kurly::postgres "$ns" ente-db-rw ente ente

credentials="$(mktemp)"
trap 'rm -f "$credentials"' EXIT
cat >"$credentials" <<YAML
db:
  host: ente-db-rw
  port: 5432
  name: ente
  user: ente
  password: ${KURLY_E2E_PASSWORD}
# museum decodes the two key material values as standard base64 and the JWT
# secret as the url-safe alphabet, so they are generated differently.
key:
  encryption: $(head -c 32 /dev/urandom | base64 | tr -d '\n')
  hash: $(head -c 64 /dev/urandom | base64 | tr -d '\n')
jwt:
  secret: $(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '\n')
YAML

kubectl --namespace="$ns" create secret generic ente \
  --from-file=credentials.yaml="$credentials" --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/ente/server.libsonnet "$ns"
kurly::boot workloads/ente/web.libsonnet "$ns"
