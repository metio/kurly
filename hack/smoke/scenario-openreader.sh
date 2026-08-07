#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the openreader workload: boot the stage on a live kind cluster from its
# own published image and wait for it to become healthy. No external dependency —
# the image carries its own database, blob store and broker.
#
# BASE_URL has no usable default (presigned upload URLs and session cookies are
# minted against it), so the in-cluster Service address is composed in here.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

kurly::namespace kurly-openreader
kubectl --namespace=kurly-openreader create secret generic openreader \
  --from-literal=AUTH_SECRET="$(head -c 32 /dev/urandom | base64 | tr -d '\n')" \
  --dry-run=client --output=yaml | kubectl apply --filename=-
kurly::boot workloads/openreader/server.libsonnet kurly-openreader \
  "+ k.env({ BASE_URL: 'http://openreader:3003' })"
