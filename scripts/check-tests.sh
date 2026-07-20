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

# Every glob-driven per-workload invariant, checked in ONE pass over each stage so
# the workload is rendered a handful of times, not once per invariant. The stages
# are independent, so the whole set fans out across cores below — adding a workload
# adds one parallel unit of work, not a re-render in every loop. Each invariant
# below is stated where it is asserted; a failure prints ::error:: and returns
# non-zero, which the parallel driver turns into an overall failure.
check_stage() {
  local stage="$1" default templates namerender strays mount over rendered metas count missing specs leaked
  local K="local k = import 'github.com/metio/kurly/main.libsonnet';"
  # The pod templates a kurly workload actually renders — found only on the
  # controller kinds it emits (a Deployment/StatefulSet/DaemonSet/Job's
  # .spec.template, a CronJob's .spec.jobTemplate.spec.template), NEVER on a
  # template a custom resource embeds (a Grafana's deployment override, a
  # Prometheus CR): those belong to an operator and no kurly feature reaches them.
  local pod_templates='[.items[]? | if .kind == "CronJob" then .spec.jobTemplate.spec.template elif (.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job") then .spec.template else empty end | select(. != null)]'

  # Render the default ONCE and reuse it across every invariant below. The shape
  # (pod workload vs custom resource) is read from it, so nothing is composed
  # before it is known — a custom-resource workload REJECTS a composed feature,
  # and composing one to probe the shape would fail for the right reason yet look
  # like the wrong one.
  default="$(jsonnet -J vendor -e "$K k.list((import '${stage}')())")" \
    || { echo "::error::${stage}: does not render" >&2; return 1; }
  templates="$(printf '%s' "$default" | jq "$pod_templates | length")"

  # Every workload must take a name, and everything it renders must follow it: a
  # namespace holds two of the same workload only if their object names differ,
  # and a workload named for its ENGINE rather than its ROLE leaks that engine
  # into every consumer. APIService is exempt — the aggregation layer mandates its
  # name be exactly `<version>.<group>`.
  namerender="$(jsonnet -J vendor -e "$K k.list((import '${stage}')(name='kurlytest'))")" \
    || { echo "::error::${stage}: does not take a name parameter" >&2; return 1; }
  strays="$(printf '%s' "$namerender" | jq -r '[.items[] | select(.kind != "APIService") | select(.metadata.name | startswith("kurlytest") | not) | "\(.kind)/\(.metadata.name)"] | join(" ")')"
  [ -z "$strays" ] || { echo "::error::${stage}: object(s) kept a name of their own after name=kurlytest: ${strays}" >&2; return 1; }

  # Every image a workload renders must follow kurly.mirror onto the private
  # registry — including an initContainer's, a grafted-on sidecar's, or a custom
  # resource's own field, which the mirror helper's field-aware rewrite can miss.
  # ConfigMap/Secret payloads are dropped first (mirror leaves application data
  # alone, so a registry-looking string there is not a leak).
  leaked="$(jsonnet -J vendor -e "$K k.mirror('registry.test', k.list((import '${stage}')()))" \
    | jq 'del(.. | objects | select(.kind == "ConfigMap" or .kind == "Secret") | .data)' \
    | grep -oE '(docker\.io|ghcr\.io|quay\.io|gcr\.io|registry\.k8s\.io|public\.ecr\.aws)/[^"]*' \
    | sort -u || true)"
  [ -z "$leaked" ] || { echo "::error::${stage}: kurly.mirror left these on a public registry: ${leaked}" >&2; return 1; }

  # Every workload that renders a PVC must let a consumer choose its storage class
  # (classes differ per cluster). Render with the class overridden — through
  # kurly.store where the mount path is known, or the workload's own param for a
  # custom resource — and fail if the rendered PVC did not move.
  if [ "$(printf '%s' "$default" | jq '([.. | objects | select(.kind? == "PersistentVolumeClaim")] | length) + ([.. | objects | select(has("volumeClaimTemplates")) | .volumeClaimTemplates[]?] | length) + ([.. | objects | select(has("storage") and (.storage | type == "object") and (.storage | has("size")))] | length)')" != "0" ]; then
    mount="$(printf '%s' "$default" | jq -r '[.. | objects | select(.name? == "store") | .mountPath?] | map(select(. != null)) | first // ""')"
    if [ -n "$mount" ]; then
      over="$(jsonnet -J vendor -e "$K k.list((import '${stage}')() + k.store('${mount}', '7Gi', storageClass='kurly-test-class'))")"
    else
      over="$(jsonnet -J vendor -e "$K k.list((import '${stage}')(storageClass='kurly-test-class'))" 2>/dev/null || true)"
      [ -n "$over" ] || { echo "::error::${stage}: renders a PVC but takes no storageClass parameter, and has no kurly.store to re-compose" >&2; return 1; }
    fi
    printf '%s' "$over" | grep -q 'kurly-test-class' \
      || { echo "::error::${stage}: renders a PVC whose storage class cannot be set" >&2; return 1; }
  fi

  # Classify by whether the workload ACCEPTS a composed pod feature, not by whether
  # it renders a pod template. A workload that authors its manifests by hand — a
  # custom resource whose pods belong to an operator, or node infrastructure like
  # spegel that fills in its own DaemonSet — writes no config a base kind reads, so
  # a composed feature would silently do nothing. It must REJECT composition (while
  # the raw + escape hatch, which touches no config, keeps working). A workload that
  # ACCEPTS a feature must make it land on every pod template it renders — so a
  # hand-authored DaemonSet is held to the reject contract even though it has a
  # template, and a base-kind workload is held to the landing contract below.
  if ! jsonnet -J vendor -e "$K k.list((import '${stage}')() + k.podLabels({ 'kurly.test/label': 'set' }))" >/dev/null 2>&1; then
    jsonnet -J vendor -e "$K k.list((import '${stage}')() + { kurlyTestProbe:: true })" >/dev/null 2>&1 \
      || { echo "::error::${stage}: rejects the raw + escape hatch, which touches no config" >&2; return 1; }
    echo "ok ${stage} (hand-authored: features rejected, name/mirror/storage hold)"
    return 0
  fi

  # It accepts a feature, so it must have a pod template for the feature to land on;
  # accepting one with nowhere to put it is the silent no-op the reject contract guards.
  if [ "$templates" = "0" ]; then
    echo "::error::${stage}: accepted kurly.podLabels() yet renders no pod template — the feature silently does nothing here" >&2
    return 1
  fi

  # A pod workload: labels/annotations, IP families, supplemental groups + DNS,
  # and the composed uid must all reach EVERY pod template and container it
  # renders — a kind that drops any of them leaves the consumer's manifest saying
  # one thing and the pod doing another (and a stray uid literal makes the whole
  # workload unrunnable on OpenShift). Render once with all of them composed.
  rendered="$(jsonnet -J vendor -e \
    "$K k.list((import '${stage}')()
       + k.podLabels({ 'kurly.test/label': 'set' })
       + k.podAnnotations({ 'kurly.test/annotation': 'set' })
       + k.supplementalGroups([4242])
       + k.dns(config={ nameservers: ['10.0.0.10'] }, hostAliases=[{ ip: '10.0.0.5', hostnames: ['db.internal'] }])
       + k.runAs(1000700000))")" \
    || { echo "::error::${stage}: failed to render with the composed pod features" >&2; return 1; }

  metas="$(printf '%s' "$rendered" | jq "$pod_templates | map(.metadata)")"
  count="$(printf '%s' "$metas" | jq 'length')"
  missing="$(printf '%s' "$metas" | jq -r '[.[] | select((.labels["kurly.test/label"] != "set") or (.annotations["kurly.test/annotation"] != "set"))] | length')"
  [ "$missing" = "0" ] || { echo "::error::${stage}: ${missing} of ${count} pod template(s) dropped podLabels/podAnnotations" >&2; return 1; }

  specs="$(printf '%s' "$rendered" | jq "$pod_templates | map(.spec)")"
  missing="$(printf '%s' "$specs" | jq -r '[.[] | select((.securityContext.supplementalGroups != [4242]) or (.dnsConfig.nameservers != ["10.0.0.10"]) or ((.hostAliases | length) != 1))] | length')"
  [ "$missing" = "0" ] || { echo "::error::${stage}: pod template(s) dropped supplementalGroups/dns" >&2; return 1; }

  strays="$(printf '%s' "$rendered" | jq -r '[.. | objects | select(has("containers") or has("initContainers")) | ((.initContainers // []) + (.containers // []))[] | select(.securityContext.runAsUser != null and .securityContext.runAsUser != 1000700000) | "\(.name)=\(.securityContext.runAsUser)"] | unique | join(" ")')"
  [ -z "$strays" ] || { echo "::error::${stage}: container(s) keep a uid of their own after kurly.runAs(): ${strays}" >&2; return 1; }

  # Every Service must follow the composed IP families — a workload that writes a
  # Service by hand otherwise keeps the cluster default on it while the rest
  # follow the consumer, and clients reach it over a family it does not speak.
  if [ "$(printf '%s' "$default" | jq '[.. | objects | select(.kind? == "Service")] | length')" != "0" ]; then
    strays="$(jsonnet -J vendor -e "$K k.list((import '${stage}')() + k.ipFamilies(['IPv6'], 'SingleStack'))" \
      | jq -r '[.. | objects | select(.kind? == "Service") | select(.spec.ipFamilies != ["IPv6"]) | .metadata.name] | join(" ")')"
    [ -z "$strays" ] || { echo "::error::${stage}: Service(s) ignored the composed IP families: ${strays}" >&2; return 1; }
  fi

  echo "ok ${stage} (name, mirror, storage, labels, families, groups/dns, uid all hold)"
}
export -f check_stage

echo "== every workload's per-stage invariants (parallel) =="
# check_stage runs in each xargs child; $1 is the child's positional (the stage
# path), expanded there, not here.
# shellcheck disable=SC2016
if ! printf '%s\n' workloads/*/*.libsonnet | xargs -P"$(nproc)" -I{} bash -c 'check_stage "$1"' _ {}; then
  echo "::error::one or more workload invariant checks failed (see above)" >&2
  exit 1
fi

# CNPG runs its pods under a ServiceAccount it creates, so the only way an IAM
# binding for object-storage backups reaches that account is the operator's
# serviceAccountTemplate — the pod-level feature cannot. A silent drop means
# backups fail to authenticate at runtime, not at render.
sat="$(jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list((import 'workloads/cnpg-cluster/cluster.libsonnet')(
     serviceAccountAnnotations={ 'eks.amazonaws.com/role-arn': 'arn:aws:iam::1:role/pg' }))" \
  | jq -r '[.. | objects | select(.kind? == "Cluster") | .spec.serviceAccountTemplate.metadata.annotations["eks.amazonaws.com/role-arn"]][0]')"
if [ "$sat" != "arn:aws:iam::1:role/pg" ]; then
  echo "::error::cnpg-cluster: serviceAccountAnnotations did not reach spec.serviceAccountTemplate (got '${sat}')" >&2
  exit 1
fi
echo "cnpg-cluster wires serviceAccountAnnotations to serviceAccountTemplate"

# Combinations that CANNOT start belong in the render, not in a CrashLoop. Each
# of these is a certain failure on a real cluster, and jsonnet has no try/catch,
# so an assert can only be observed by failing — which an assertion suite cannot
# express.
negative() { # <description> <expression that MUST fail to render>
  if jsonnet -J vendor -e "$2" >/dev/null 2>&1; then
    echo "$1: rendered instead of failing" >&2
    exit 1
  fi
  echo "assert fired as expected: $1"
}
positive() { # <description> <expression that MUST render>
  if ! jsonnet -J vendor -e "$2" >/dev/null 2>&1; then
    echo "$1: failed to render, but this combination is legitimate" >&2
    exit 1
  fi
  echo "renders as expected: $1"
}

K="local k = import 'github.com/metio/kurly/main.libsonnet';"
# uid 0 under runAsNonRoot: the kubelet refuses the container before it starts.
negative "runAsUser 0 contradicts runAsNonRoot" \
  "$K k.list(k.worker('w', 'img:1') + k.runAs(0))"
# Every honest way to actually run as root must still work, or the assert is a
# wall rather than a guard.
positive "runAs(0) + rootUser()" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.rootUser())"
positive "runAs(0) + security.baseline" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.security.baseline)"
positive "runAs(0) + security.privileged" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.security.privileged)"
# An arbitrary high uid is what OpenShift assigns; it must never trip the guard.
positive "an OpenShift-style arbitrary uid" "$K k.list(k.worker('w', 'img:1') + k.runAs(1000700000))"

# dnsPolicy 'None' replaces resolv.conf wholesale, so a pod with no nameservers
# of its own has no resolver at all — the apiserver rejects it.
negative "dnsPolicy None with no nameservers" \
  "$K k.list(k.worker('w', 'img:1') + k.dns(policy='None'))"
positive "dnsPolicy None with its own nameservers" \
  "$K k.list(k.worker('w', 'img:1') + k.dns(policy='None', config={ nameservers: ['10.0.0.10'] }))"

# tik is one writer on one ReadWriteOnce volume; a second pod cannot attach it.
negative "tik scaled past its single writer" \
  "$K k.list((import 'workloads/tik/backend.libsonnet')() + k.replicas(3))"
positive "tik at its one replica" \
  "$K k.list((import 'workloads/tik/backend.libsonnet')() + k.replicas(1))"

# huge_pages=on without an allocation: PostgreSQL refuses to start, by design.
negative "huge_pages=on with no hugepages resource" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'on'})"
# Kubernetes rejects a pod whose hugepages request and limit differ.
negative "a hugepages request that differs from its limit" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(resources={limits: {'hugepages-2Mi': '2Gi'}, requests: {'hugepages-2Mi': '1Gi'}})"
positive "huge_pages=on with a matching allocation" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'on'}, resources={limits: {'hugepages-2Mi': '2Gi'}, requests: {'hugepages-2Mi': '2Gi'}})"
positive "huge_pages=try with no allocation" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'try'})"

# An app's memory flag and the container limit are two views of one number, and
# only the limit is enforced by the kernel. kurly.resources() REPLACES the limits
# object rather than merging, so composing it for an unrelated reason drops the
# derived limit and leaves the cache unbounded — and overriding it directly makes
# the flag and the cgroup disagree, which is an OOMKill at exactly the moment the
# cache fills.
negative "memcached with a hand-set memory limit" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=1024) + k.resources(limits={memory: '128Mi'}))"
negative "memcached losing its derived limit to an unrelated one" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=1024) + k.resources(limits={'ephemeral-storage': '1Gi'}))"
negative "dragonfly with a hand-set memory limit" \
  "$K k.list((import 'workloads/dragonfly/instance.libsonnet')(maxMemoryMB=2048, threads=4) + k.resources(limits={memory: '256Mi'}))"
# Sizing through the workload's own knob must keep working — the assert is a
# guard, not a wall.
positive "memcached sized through memoryMB" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=4096))"
positive "dragonfly sized through maxMemoryMB" \
  "$K k.list((import 'workloads/dragonfly/instance.libsonnet')(maxMemoryMB=4096, threads=4))"

# Dragonfly exits at startup when maxmemory is under 256MiB per io thread, so
# the workload asserts the floor at render — the pod would otherwise CrashLoop
# with the reason buried in its log.
if jsonnet -J vendor -e "(import 'workloads/dragonfly/instance.libsonnet')(threads=4, maxMemoryMB=512)" >/dev/null 2>&1; then
  echo "dragonfly rendered below its memory floor instead of failing" >&2
  exit 1
fi
echo "dragonfly memory-floor assert fired as expected"
