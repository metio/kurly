#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the solectrus workload. HAND-WRITTEN, because solectrus declares TWO
# database dependencies — PostgreSQL for its own records and InfluxDB for the
# measurements — and the generator provisions one database per workload. It also
# needs the InfluxDB token in its Secret to be the same token InfluxDB was set up
# with, which nothing can derive.
#
# The Redis URL is overridden without credentials: solectrus waits for its cache
# by splitting REDIS_URL on ':' and passing the tail to `nc`, so a password in
# the URL is read as the port and the wait never finishes. The cache is therefore
# started without one, which is what that parse expects.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-solectrus
influxToken=kurly-e2e-influx-token

kurly::namespace "$ns"
kurly::postgres "$ns" solectrus-db-rw solectrus solectrus
kurly::cache "$ns" solectrus-cache-headless ""
kurly::influxdb "$ns" influxdb solectrus solectrus "$influxToken"

# The generated Secret carries the keys the catalogue declares; INFLUX_TOKEN is
# `external` there precisely because it belongs to a server nobody had yet, so it
# is set here to the token InfluxDB was just created with.
kurly::secret "$ns" solectrus workloads/solectrus/server.libsonnet
kubectl --namespace="$ns" patch secret solectrus --type=merge \
  --patch="{\"stringData\":{\"INFLUX_TOKEN\":\"${influxToken}\",\"REDIS_URL\":\"redis://solectrus-cache-headless:6379\"}}"

kurly::boot workloads/solectrus/server.libsonnet "$ns"
