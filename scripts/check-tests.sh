# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The assertion suites plus the requiresService negative check. jsonnet has no
# try/catch, so the "compose an exposure onto a Service-less workload must
# fail" invariant can't live in an assertion file — it is exercised here.

# The k8s-libsonnet dependency floats at upstream HEAD (matching the JOI
# images); vendor it fresh so the suites test what clusters actually run.
jb install

# The workload stages below import kurly by its canonical path — the one JaaS
# resolves in a cluster — so resolve it locally through the vendor tree, as
# check-examples and check-catalog do.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

# Every tests/*_test.jsonnet is an assertion suite whose every field is a
# std.assertEqual (unit tests, plus the order-independence, invariant, and
# metamorphic batteries); assert all fields evaluate true.
for suite in tests/*_test.jsonnet; do
  jsonnet -J vendor "$suite" | jq -e 'to_entries | all(.value == true)' >/dev/null \
    || { echo "::error::assertion failed in $suite" >&2; exit 1; }
  echo "assertions passed: $suite"
done

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

# Every image a workload renders must follow kurly.mirror onto the private
# registry. The assertion suite can only check mirror against apps it writes
# itself, which is precisely the blind spot that let kurly.image() redirect the
# valkey cache's main container while its initContainer and sidecar kept pulling
# from docker.io. So render each REAL workload through mirror and look for a
# public registry surviving anywhere in the output — that catches an image
# mirror cannot see (an initContainer, a grafted-on sidecar, a custom resource's
# own field) rather than only the fields it already knows about.
#
# The glob is the point: a workload added tomorrow is covered without editing
# this file, and a workload that hides an image somewhere new fails here.
#
# ConfigMap and Secret payloads are dropped first: mirror deliberately leaves
# application data alone, so a registry-looking string in there is not a leak.
echo "== mirror redirects every image in every workload =="
for stage in workloads/*/*.libsonnet; do
  leaked="$(
    jsonnet -J vendor -e \
      "local k = import 'github.com/metio/kurly/main.libsonnet'; k.mirror('registry.test', k.list((import '${stage}')()))" \
      | jq 'del(.. | objects | select(.kind == "ConfigMap" or .kind == "Secret") | .data)' \
      | grep -oE '(docker\.io|ghcr\.io|quay\.io|gcr\.io|registry\.k8s\.io|public\.ecr\.aws)/[^"]*' \
      | sort -u || true
  )"
  if [ -n "$leaked" ]; then
    echo "::error::${stage}: kurly.mirror left these on a public registry:" >&2
    printf '  %s\n' "$leaked" >&2
    exit 1
  fi
  echo "mirror covers every image in $stage"
done
