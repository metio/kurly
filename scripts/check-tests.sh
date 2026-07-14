# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The assertion suite plus the requiresService negative check. jsonnet has no
# try/catch, so the "compose an exposure onto a Service-less workload must
# fail" invariant can't live in the assertion file — it is exercised here.

# The k8s-libsonnet dependency floats at upstream HEAD (matching the JOI
# images); vendor it fresh so the suite tests what clusters actually run.
jb install

# Every field in the suite is a std.assertEqual; assert they all evaluate true.
jsonnet -J vendor tests/kurly_test.jsonnet | jq -e 'to_entries | all(.value == true)' >/dev/null
echo "all assertions passed"

# The requiresService assert must fire when an exposure is composed onto a
# workload with no Service.
if jsonnet -J vendor -e "local kurly = import 'main.libsonnet'; kurly.worker('w', 'img:1') + kurly.expose.ingress('h.example.com')" >/dev/null 2>&1; then
  echo "composing an exposure onto a worker rendered instead of failing" >&2
  exit 1
fi
echo "requiresService assert fired as expected"

# The exclusion assert must fire when two members of one exclusion group are
# composed — here two exposure recipes on one workload.
if jsonnet -J vendor -e "local kurly = import 'main.libsonnet'; kurly.http('h', 'img:1') + kurly.expose.ingress('h.example.com') + kurly.expose.gateway('h.example.com', 'gw')" >/dev/null 2>&1; then
  echo "composing two exposures rendered instead of failing" >&2
  exit 1
fi
echo "exposure exclusion assert fired as expected"
