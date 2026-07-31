# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# dex reads its whole configuration from a Secret mounted at /etc/dex, and kurly
# authors none — an issuer URL, the connectors and the static clients are things
# only a deployment knows. This is the smallest configuration that starts: a
# postgres backend pointing at the database the smoke provisions, and one static
# client so the server has something to serve.
#
# Sourced with $ns set, by the fast scenario and by the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

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
