#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the owntracks-recorder workload. The Recorder subscribes to an MQTT broker
# on start and exits when it cannot reach one, so the scenario boots kurly's own
# mosquitto workload beside it and points the Recorder at that Service — which also
# proves the pairing the two workloads exist for.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-owntracks-recorder
kurly::namespace "$ns"

kurly::boot workloads/mosquitto/server.libsonnet "$ns"

kurly::boot workloads/owntracks-recorder/server.libsonnet "$ns" \
  "+ k.env({ OTR_STORAGEDIR: '/store', OTR_HOST: 'mosquitto', OTR_PORT: '1883' })"
