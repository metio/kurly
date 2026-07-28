#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the znc workload. ZNC refuses to start without a znc.conf, and its own
# generator (`znc --makeconf`) is interactive — so the smoke seeds the smallest
# usable config onto the volume from a ConfigMap, the way an operator would after
# running makeconf once. ZNC rewrites that file as it runs, which is why it is
# copied onto the volume rather than mounted read-only.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-znc
kurly::namespace "$ns"

config="$(mktemp -p . znc-smoke.XXXXXX.conf)"
trap 'rm -f "$config"' EXIT
cat >"$config" <<'CONF'
Version = 1.10.2
<Listener listener0>
	Port = 6697
	IPv4 = true
	IPv6 = true
	SSL = false
</Listener>
<User admin>
	Admin = true
	Nick = admin
	<Pass password>
		Method = plain
		Hash = kurly
	</Pass>
</User>
CONF

kurly::boot workloads/znc/server.libsonnet "$ns" \
  "+ k.config({ 'znc.conf': importstr '${config}' }, '/seed') + k.initContainer({ name: 'seed', image: 'docker.io/library/busybox:1.37.0', command: ['sh', '-c', 'test -f /znc-data/configs/znc.conf || { mkdir -p /znc-data/configs; cp /seed/znc.conf /znc-data/configs/znc.conf; }'], volumeMounts: [{ name: 'store', mountPath: '/znc-data' }, { name: 'config', mountPath: '/seed' }] })"
