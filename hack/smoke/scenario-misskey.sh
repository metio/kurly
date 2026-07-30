#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the misskey workload. Misskey is configured by a default.yml holding the
# instance URL and its database and Redis connections — kurly authors none, because
# it carries credentials — so the smoke supplies the smallest one that boots the
# server against the throwaway PostgreSQL and Valkey.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-misskey
kurly::namespace "$ns"

kurly::postgres "$ns" misskey-db-rw misskey misskey
kurly::cache "$ns" misskey-cache-headless ""

config="$(mktemp)"
trap 'rm -f "$config"' EXIT
cat >"$config" <<YAML
url: http://misskey.example.com/
port: 3000
db:
  host: misskey-db-rw
  port: 5432
  db: misskey
  user: misskey
  pass: ${KURLY_E2E_PASSWORD}
redis:
  host: misskey-cache-headless
  port: 6379
  pass: ${KURLY_E2E_PASSWORD}
id: aidx
YAML

kubectl --namespace="$ns" create secret generic misskey \
  --from-file=default.yml="$config" --dry-run=client --output=yaml | kubectl apply --filename=-

kurly::boot workloads/misskey/server.libsonnet "$ns"
