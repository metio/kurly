#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the druid workload. Hand-written rather than generated, because the
# deep-storage endpoint is namespace-local: Druid reaches the throwaway SeaweedFS
# through its HEADLESS service, an address that only exists once this scenario has
# created it, so it is passed as a parameter rather than baked into the stage as a
# default that would be wrong everywhere Druid is really deployed.
#
# The stages are booted in the order a StageSet would gate them: the coordinator
# creates the metadata tables the rest read.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-druid
kurly::namespace "$ns"

# Metadata (datasources, segments, task state) and deep storage (the segments
# themselves plus the task logs). Both are hard requirements: Druid does not boot
# without a metadata store, and a middleManager cannot publish a segment nowhere.
kurly::postgres "$ns" druid-db-rw druid druid
kurly::objectstorage "$ns" druid

# The credentials, as the env var names the image translates into Druid
# properties. SeaweedFS in this mode ignores the S3 keys, but the client still
# signs its requests, so they have to be present.
kubectl --namespace="$ns" create secret generic druid \
  --from-literal=druid_metadata_storage_connector_password="$KURLY_E2E_PASSWORD" \
  --from-literal=druid_s3_accessKey=druid \
  --from-literal=druid_s3_secretKey="$KURLY_E2E_PASSWORD" \
  --dry-run=client --output=yaml | kubectl apply --filename=-

params="s3Endpoint='http://seaweedfs-headless:8333'"

kurly::boot workloads/druid/coordinator.libsonnet "$ns" "" "$params"
kurly::boot workloads/druid/historical.libsonnet "$ns" "" "$params"
kurly::boot workloads/druid/middle-manager.libsonnet "$ns" "" "$params"
kurly::boot workloads/druid/broker.libsonnet "$ns" "" "$params"
kurly::boot workloads/druid/router.libsonnet "$ns" "" "$params"

# The services are only really a CLUSTER once they have discovered one another
# through the Kubernetes API — every pod being Ready says each process started,
# not that any of them found the others. The router proxies the coordinator's
# view of the cluster, so asking it is one question that exercises the whole
# discovery path.
kubectl --namespace="$ns" run druid-discovery --rm --attach --restart=Never \
  --image=docker.io/curlimages/curl:8.21.0 --command -- \
  curl -sf --retry 20 --retry-delay 5 --retry-all-errors \
  http://druid-router:8888/druid/coordinator/v1/cluster
