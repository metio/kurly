# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Prerequisites for misskey: the configuration Secret the workload reads and
# kurly deliberately does not author, since only a deployment knows what is
# in it. Sourced with $ns set, by the fast scenario and the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

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
