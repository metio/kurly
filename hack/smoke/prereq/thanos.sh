# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Prerequisites for thanos: the configuration Secret the workload reads and
# kurly deliberately does not author, since only a deployment knows what is
# in it. Sourced with $ns set, by the fast scenario and the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

objstore="$(mktemp)"
trap 'rm -f "$objstore"' EXIT
cat >"$objstore" <<YAML
type: S3
config:
  bucket: thanos
  endpoint: seaweedfs-0.seaweedfs-headless.${ns}.svc:8333
  insecure: true
  access_key: thanos
  secret_key: ${KURLY_E2E_PASSWORD}
YAML

kubectl --namespace="$ns" create secret generic thanos-objstore \
  --from-file=objstore.yaml="$objstore" --dry-run=client --output=yaml | kubectl apply --filename=-
