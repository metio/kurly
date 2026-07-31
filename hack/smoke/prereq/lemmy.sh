# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Prerequisites for lemmy: the configuration Secret the workload reads and
# kurly deliberately does not author, since only a deployment knows what is
# in it. Sourced with $ns set, by the fast scenario and the deep check alike.

# The key pict-rs authenticates the backend with. Generated HERE rather than in
# the scenario: the deep check sources this file and never runs the scenario, so
# anything the configuration below interpolates has to be defined in it.
: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

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
