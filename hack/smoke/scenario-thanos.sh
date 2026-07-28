#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the thanos workload. Every stage that touches long-term storage reads one
# objstore.yaml from a Secret naming the bucket — kurly authors none, because it
# carries the object store's credentials. The scenario stands up a SeaweedFS S3
# gateway, points the objstore config at it, and boots all six stages against it.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-thanos
kurly::namespace "$ns"

kurly::cache "$ns" thanos-cache-headless
kurly::objectstorage "$ns" thanos

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

kurly::boot workloads/thanos/compact.libsonnet "$ns"
kurly::boot workloads/thanos/store.libsonnet "$ns"
kurly::boot workloads/thanos/query.libsonnet "$ns"
kurly::boot workloads/thanos/query-frontend.libsonnet "$ns"
kurly::boot workloads/thanos/receive.libsonnet "$ns"
# The ruler is a custom resource an operator reconciles, so it is schema-checked
# rather than booted — the same treatment every operator-backed stage gets.
kurly::validate_cr "$ns" workloads/thanos/ruler.libsonnet \
  "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.87.0/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml"
