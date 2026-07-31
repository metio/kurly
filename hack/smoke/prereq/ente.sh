# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Prerequisites for ente: the configuration Secret the workload reads and
# kurly deliberately does not author, since only a deployment knows what is
# in it. Sourced with $ns set, by the fast scenario and the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

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
