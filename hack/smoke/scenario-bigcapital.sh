#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the bigcapital workload. It is the one workload that needs three
# different backing services at once — MariaDB for its system and tenant
# databases, MongoDB for its document store, and Redis for its queues — so the
# generic "one postgres, one valkey" provisioning the generator emits does not
# fit, and the scenario stands them up itself. All three stages (gateway, server,
# webapp) then boot in the same namespace.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-bigcapital
kurly::namespace "$ns"

kurly::mysql "$ns" bigcapital-mariadb bigcapital bigcapital
kurly::mongodb "$ns" bigcapital-mongo
# Its queue configuration carries no password, so the cache is left open.
kurly::cache "$ns" bigcapital-cache ""
kurly::objectstorage "$ns" bigcapital

kurly::secret "$ns" bigcapital workloads/bigcapital/server.libsonnet
kurly::boot workloads/bigcapital/server.libsonnet "$ns" \
  "+ k.env({ S3_ENDPOINT: 'http://seaweedfs-0.seaweedfs-headless.${ns}.svc:8333' })"
kurly::boot workloads/bigcapital/gateway.libsonnet "$ns"
kurly::boot workloads/bigcapital/webapp.libsonnet "$ns"
