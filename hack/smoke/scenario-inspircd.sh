#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the inspircd workload. InspIRCd will not start without an inspircd.conf,
# and kurly authors none (a real one carries the network's identity, opers, and
# TLS material), so the smoke mounts the smallest configuration that serves IRC:
# one server block, one listening port, and the modules a bare server needs.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-inspircd
kurly::namespace "$ns"

# The config is rendered into the workload's own ConfigMap by kurly.config, so it
# is read from a file next to the scenario at render time.
config="$(mktemp -p . inspircd-smoke.XXXXXX.conf)"
trap 'rm -f "$config"' EXIT
cat >"$config" <<'CONF'
<server name="irc.example.com" description="kurly smoke" network="kurly">
<admin name="kurly" nick="kurly" email="kurly@example.com">
<bind address="" port="6697" type="clients">
<class name="Users" commandrate="1000" fakelag="on" pingfreq="120" sendq="262144" recvq="8192" localmax="100" globalmax="100" maxchans="20" threshold="10">
<connect name="main" allow="*" class="Users">
<files motd="motd.txt">
<options prefixquit="Quit: " suffixquit="" prefixpart="&quot;" suffixpart="&quot;" xlinemessage="You are banned" allowhalfop="yes">
<log method="file" type="* -USERINPUT -USEROUTPUT" level="default" target="/dev/stdout">
CONF

kurly::boot workloads/inspircd/server.libsonnet "$ns" \
  "+ k.config({ 'inspircd.conf': importstr '${config}' }, '/inspircd/conf')"
