#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the shipshipship workload: boot the stage on a live kind cluster from
# its own published image and wait for it to become healthy. No external
# dependency. The Secret is minted here rather than by kurly::secret, since the
# admin credentials and the token secret are all the stage reads.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

kurly::namespace kurly-shipshipship
kubectl -n kurly-shipshipship create secret generic shipshipship \
  --from-literal=ADMIN_USERNAME=admin \
  --from-literal=ADMIN_PASSWORD="$KURLY_E2E_PASSWORD" \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
kurly::boot workloads/shipshipship/server.libsonnet kurly-shipshipship
