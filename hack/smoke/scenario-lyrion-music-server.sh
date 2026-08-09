#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the lyrion-music-server workload: boot every stage on a live kind cluster
# from its own published image and wait for it to become healthy. No external
# dependency.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

kurly::boot workloads/lyrion-music-server/server.libsonnet kurly-lyrion-music-server "" ""
