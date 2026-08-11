#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Shared helpers for the per-workload e2e scenarios (hack/smoke/scenario-*.sh).
# Each scenario is self-contained: it installs whatever operator it needs, renders
# the workload the way a consumer would, applies it to the current cluster (a kind
# cluster the e2e workflow owns), and waits for it to become healthy — proving the
# manifests kurly produces actually RUN, not just that they schema-validate.
set -euo pipefail

# kurly imports k8s-libsonnet (vendored fresh) and resolves its own canonical
# path through a vendor symlink, exactly as the render gates do.
kurly::vendor() {
  mkdir -p vendor/github.com/metio
  ln -sfn ../../.. vendor/github.com/metio/kurly
  # Idempotent: skip the (slow, and parallel-unsafe) jb install once the vendor
  # tree is populated, so many scenarios can share one pre-vendored checkout.
  [ -f vendor/.kurly-vendored ] && return 0
  jb install >/dev/null && touch vendor/.kurly-vendored
}

# Renders a workload stage (a function(params) app) to a kind: List, the way a
# consumer's JsonnetSnippet does. Extra Jsonnet composed onto the app is passed as
# $2 (e.g. "+ k.hostUsers()") — kind inside GitHub Actions cannot nest user
# namespaces, so kurly-pod workloads relax that one knob for the smoke.
kurly::render() {
  local stage="$1" extra="${2:-}" params="${3:-}"
  # `extra` composes onto an already-built app with `+`; `params` is passed when
  # the stage function is CALLED, which is the only way to reach an argument.
  # metrics-server cannot scrape a kind kubelet without kubeletInsecureTLS, and
  # no amount of composing reaches that — the deep walk has always passed both,
  # and a fast scenario that silently dropped one booted a stage configured
  # differently from the one it claimed to prove.
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')(${params}) ${extra})"
}

# Whether composed features apply to a stage, as `yes` or `no` on stdout.
#
# The deep walk composes hostUsers() onto everything, because kind cannot nest
# user namespaces. A workload that authors PLAIN MANIFESTS rather than a
# composable base rejects every feature with an assert of its own — and for one
# of those the override is not merely impossible but unnecessary, since a
# workload that composes nothing never asked for a user namespace to begin with.
#
# Returns non-zero when the stage does not render AT ALL, which must not read as
# `no`: a broken stage and a plain-manifest one both fail the composed render,
# and treating them alike reported spegel — whose DaemonSet renders perfectly —
# as a workload with no controller to deliver.
kurly::composes_features() {
  local stage="$1"
  if kurly::render "$stage" "+ k.hostUsers()" >/dev/null 2>&1; then
    echo yes
    return 0
  fi
  if kurly::render "$stage" >/dev/null 2>&1; then
    echo no
    return 0
  fi
  return 1
}

# Creates a namespace idempotently.
# A FRESH NAMESPACE PER RUN, echoed back for the caller to use. Re-running a
# workload shortly after its own cleanup is the case that breaks a fixed name:
# deleting a namespace is not instant, and one still draining accepts a create
# while refusing everything put into it — pods come back "already exists" from
# the dying generation, or never schedule. A walk that re-ran eight healthy
# workloads minutes after cleaning them up failed all eight for that reason.
#
# The suffix makes the collision impossible rather than survivable.
# kurly::cleanup_workload already matches `kurly-<id>(-…)`, so these are removed
# by the same call that removed the fixed-name ones.
#
#   ns="$(kurly::namespace_unique kurly-<id>)"
kurly::namespace_unique() {
  local ns="$1-$(tr -dc a-z0-9 </dev/urandom | head -c 6)"
  kubectl create namespace "$ns" --dry-run=client --output=yaml | kubectl apply --filename=- >/dev/null
  printf '%s' "$ns"
}

kurly::namespace() {
  # WAIT OUT A TERMINATING NAMESPACE FIRST. Deleting one is not instant — the
  # cleanup that precedes a re-run gives it 180 seconds and then moves on — and a
  # namespace still draining accepts the create without complaint while refusing
  # everything put INTO it: pods come back "already exists" from the dying
  # generation, or never schedule at all. The workload then looks broken, and a
  # walk that re-ran eight healthy workloads minutes after their own cleanup
  # failed all eight for exactly this.
  local deadline=$((SECONDS + 300))
  while kubectl get namespace "$1" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Terminating; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "::error::namespace $1 is still Terminating after 300s — refusing to boot into it" >&2
      return 1
    fi
    sleep 3
  done
  kubectl create namespace "$1" --dry-run=client --output=yaml | kubectl apply --filename=-
}

# CI-verifies a stage's declared minimum resources: renders it with the catalog's
# `minimumResources` as its requests AND (for memory + ephemeral-storage, the two
# that fail a pod rather than merely throttle it) its LIMITS, applies it to a
# throwaway namespace, and waits for its controller to roll out. If the declared
# minimum is too low the pod OOMs or is evicted and never becomes Ready, so this
# fails — turning the catalog number into a verified-sufficient floor rather than a
# guess. Called from a workload's OWN e2e scenario (gated on that workload's
# paths), so the check runs only when the workload it verifies changes.
#
#   kurly::verify_min_resources workloads/seaweedfs/server.libsonnet
kurly::verify_min_resources() {
  local stage="$1" extra="${2:-}"
  local mr cpu mem eph
  mr="$(jq -c --arg ip "github.com/metio/kurly/${stage}" \
    '.workloads[].stages[] | select(.importPath==$ip) | .minimumResources // empty' .build/catalog.json)"
  [ -n "$mr" ] || { echo "::error::${stage} declares no minimumResources in the catalog"; return 1; }
  cpu="$(jq -r '.cpu' <<<"$mr")"; mem="$(jq -r '.memory' <<<"$mr")"; eph="$(jq -r '.ephemeralStorage' <<<"$mr")"
  local ns=min-resources
  kurly::namespace "$ns" >/dev/null
  echo "== verify ${stage} starts at its declared minimum (cpu=${cpu}, memory=${mem}, ephemeral-storage=${eph}) =="
  # requests carry the cpu floor; memory + ephemeral-storage are also limits, so an
  # insufficient number OOMs / evicts the pod instead of silently over-scheduling.
  # kind-in-CI cannot nest user namespaces, so hostUsers is relaxed (as elsewhere).
  local render="+ k.resources(requests={cpu: '${cpu}', memory: '${mem}', 'ephemeral-storage': '${eph}'}, limits={memory: '${mem}', 'ephemeral-storage': '${eph}'}) + k.hostUsers() ${extra}"
  kurly::render "$stage" "$render" | kubectl apply --namespace="$ns" --filename=-
  local ctrl
  for ctrl in $(kubectl --namespace="$ns" get deployment,statefulset --output=name); do
    kubectl --namespace="$ns" rollout status "$ctrl" --timeout=300s \
      || { echo "::error::${stage} did not become Ready at its declared minimum resources"; kurly::diagnose "$ns"; return 1; }
  done
  # Free the namespace so a second stage in the same scenario starts clean.
  kubectl delete namespace "$ns" --wait=false >/dev/null 2>&1 || true
  echo "ok: ${stage} starts at its declared minimum resources"
}

# Boots one workload stage on the live cluster the way a consumer would: render
# its defaults, apply, and wait for every controller it creates to become healthy
# — proving the stage RUNS, not merely that it schema-validates. hostUsers is
# relaxed because kind-in-CI cannot nest user namespaces; every other hardening
# knob the stage ships (read-only rootfs, dropped caps, seccomp, pinned uid) is
# still exercised. A CronJob stage carries no long-running controller, so it is
# triggered once as a Job and awaited. Extra Jsonnet composed onto the app is
# passed as $3 (e.g. a Secret-backed env the app needs to boot).
#
# Waits for a controller to become Ready, but FAILS FAST the moment one of its
# pods is clearly broken — CrashLoopBackOff, an image that will not pull
# (ImagePullBackOff/ErrImagePull), or repeated restarts — instead of blocking the
# full rollout timeout. Faster feedback that a version/manifest is broken, and it
# keeps the single-cluster e2e walk moving. Timeout via KURLY_ROLLOUT_TIMEOUT
# (seconds, default 300).
# The restart ceiling is a heuristic, and a MULTI-COMPONENT app can exceed it while
# starting correctly: the check looks at every pod in the namespace, so a sibling
# waiting for another to finish its migrations fails the controller being waited
# on. Mastodon's sidekiq restarts three times against a schema its web pod has not
# created yet, then settles with every pod Ready. Raise it per workload
# (extra.json's maxRestarts) rather than globally, which would blunt the fast
# feedback that a genuinely broken image gives.
kurly::await_ready() {
  local ns="$1" ctrl="$2" timeout="${KURLY_ROLLOUT_TIMEOUT:-300}" maxRestarts="${KURLY_MAX_RESTARTS:-3}" deadline waitreason restarts
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if kubectl --namespace="$ns" rollout status "$ctrl" --timeout=4s >/dev/null 2>&1; then
      return 0
    fi
    # TERMINAL states only. A pod that cannot get its image or its configuration
    # will never roll out however long it is given, so bail immediately.
    #
    # CrashLoopBackOff is NOT in that list, because it is not terminal: it is also
    # what a correct multi-component app looks like while it waits for a sibling —
    # mastodon's web pod crash-loops against a schema its own migration has not
    # finished writing, and then serves. Treating it as broken failed the workload
    # for doing the only thing it can do. It is caught by the restart ceiling
    # below instead, which a workload can raise when restarts are part of its
    # start-up, and which still fails a genuinely broken image within seconds.
    waitreason="$(kubectl --namespace="$ns" get pods \
      -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' 2>/dev/null \
      | grep -E 'ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName' | head -1 || true)"
    if [ -n "$waitreason" ]; then
      echo "::error::${ctrl}: pod broken (${waitreason})"; return 1
    fi
    restarts="$(kubectl --namespace="$ns" get pods \
      -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{end}' 2>/dev/null \
      | sort -rn | head -1 || true)"
    if [ "${restarts:-0}" -ge "$maxRestarts" ]; then
      echo "::error::${ctrl}: pod restarting repeatedly (restarts=${restarts})"; return 1
    fi
    sleep 4
  done
  echo "::error::${ctrl}: not Ready within ${timeout}s"; return 1
}

#   kurly::boot workloads/adguardhome/server.libsonnet kurly-adguardhome
# --- the long-lived cluster and the space it leaks ---------------------------
#
# The fleet runs on ONE cluster that stays up, with the delivery stack installed
# once. Standing Flux, JaaS and stageset up per workload cost minutes each and
# pulled their images again every time; keeping them is what makes a walk of four
# hundred workloads finish.
#
# Idempotent by CHECKING FIRST, not by re-applying: `helm upgrade --install` and
# `kubectl apply` are safe to repeat but not free, and repeating them four
# hundred times is most of a run.
kurly::infrastructure_ready() {
  kubectl get deployment source-controller --namespace=flux-system >/dev/null 2>&1 &&
    kubectl get deployment --namespace=jaas-system >/dev/null 2>&1 &&
    kubectl get deployment --namespace=stageset-system >/dev/null 2>&1
}

kurly::ensure_infrastructure() {
  if kurly::infrastructure_ready; then
    echo "== delivery stack already installed — keeping it =="
    return 0
  fi
  echo "== installing the delivery stack (once, for the whole walk) =="
  kurly::install_flux
  kurly::install_jaas
  kurly::install_stageset
}

# THE DISK IS THE THING THAT ENDS A FLEET RUN, and a deleted namespace is not
# enough on its own. Deleting a PersistentVolumeClaim releases its volume, and
# local-path only removes the directory when it observes the delete — a
# provisioner that is behind, a PV left Released, or a claim whose namespace went
# away underneath it all leave gigabytes on the node with nothing pointing at
# them. Three kind clusters holding those directories filled 114GB of this host.
#
# So after each workload the node's provisioner directory is reconciled against
# the PersistentVolumes that actually exist, and anything else is removed.
#
# Done through a POD rather than `podman exec`: the node is reachable with
# kubectl alone, which is true in CI and on a host whose rootless podman needs a
# corrected storage configuration before it can see its own containers.
kurly::purge_pv_data() {
  local keep
  # The PVs that still exist are the directories worth keeping. Everything the
  # provisioner has on disk beyond this list is backing nothing.
  keep="$(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')"
  kubectl delete job kurly-purge-pv --namespace=default --ignore-not-found >/dev/null 2>&1 || true
  kubectl apply --namespace=default --filename=- >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata: { name: kurly-purge-pv }
spec:
  ttlSecondsAfterFinished: 60
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: purge
          image: docker.io/library/busybox:1.37
          env: [{ name: KEEP, value: "${keep}" }]
          command:
            - /bin/sh
            - -c
            - |
              cd /data 2>/dev/null || exit 0
              for dir in *; do
                [ -e "\$dir" ] || continue
                # THE DIRECTORY IS NOT NAMED AFTER THE VOLUME ALONE. local-path
                # names it <pv>_<namespace>_<claim>, while the keep-list holds bare
                # PV names, so comparing the whole directory matched NOTHING and
                # deleted every volume on the node — including live ones. It went
                # unnoticed because a walk purges just after deleting the
                # namespace, when the data is worthless anyway; the damage lands
                # on a volume that OUTLIVES its workload, whose pod then cannot
                # start with "no such file or directory" for its own mount.
                pv="\${dir%%_*}"
                case " \$KEEP " in
                  *" \$pv "*) ;;
                  *) rm -rf "\$dir" ;;
                esac
              done
          volumeMounts: [{ name: data, mountPath: /data }]
      volumes:
        - name: data
          hostPath: { path: /var/local-path-provisioner, type: DirectoryOrCreate }
EOF
  kubectl wait --namespace=default --for=condition=complete job/kurly-purge-pv --timeout=120s >/dev/null 2>&1 || true
  kubectl delete job kurly-purge-pv --namespace=default --ignore-not-found >/dev/null 2>&1 || true
}

# --- measuring what a workload actually costs to start -----------------------
#
# Every scenario already boots its workload on a live cluster and watches it
# become Ready, so the two numbers a consumer most wants — how long that took and
# how much memory it needed — are being produced and thrown away. These helpers
# keep them.
#
# Memory comes from the kubelet's own resource-metrics endpoint rather than
# `kubectl top`, which needs metrics-server installed: a measurement that only
# works on a cluster carrying an add-on would be missing for exactly the runs
# nobody set up specially. It is the same endpoint metrics-server itself scrapes.
# NOT /stats/summary, which looks like the obvious choice and returns 500 here —
# it collects image-filesystem statistics first, and that fails outright under
# the fuse-overlayfs snapshotter this host's rootless podman requires, taking
# every pod's memory down with it.
#
# PEAK-AT-STARTUP AND STEADY-STATE ARE SEPARATE NUMBERS and both are recorded,
# because most of the resource defaults in this catalogue are wrong in the same
# direction: sized for the migration rather than the service, or the reverse.
# Publishing one number would repeat that mistake in a field that looks measured.
kurly::_pod_memory() {
  local ns="$1" name="$2" node pods
  node="$(kubectl --namespace="$ns" get pods -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"
  [ -n "$node" ] || { printf 0; return 0; }
  # ONLY THE WORKLOAD'S OWN PODS, selected by ITS NAME. The namespace also holds
  # whatever throwaway postgres, valkey, mongodb or object store the scenario
  # provisioned, and summing the namespace measures the harness instead: 433Mi
  # for an application that uses 348Mi and dependencies that use the rest.
  #
  # managed-by=kurly is NOT enough on its own, which is only visible from the
  # object-storage case: that provisioner stands up kurly's own seaweedfs
  # workload, so it carries the same managed-by label and was counted as the
  # application's memory. The name label is what separates one kurly workload
  # from another in a shared namespace.
  #
  # A sidecar the workload declares itself lives in the pod and is still counted,
  # which is right — it is part of what the workload costs to run.
  pods="$(kubectl --namespace="$ns" get pods \
    -l "app.kubernetes.io/managed-by=kurly,app.kubernetes.io/name=${name}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)"
  [ -n "$pods" ] || { printf 0; return 0; }
  kubectl get --raw "/api/v1/nodes/${node}/proxy/metrics/resource" 2>/dev/null \
    | awk -v ns="$ns" -v pods="$pods" '
        BEGIN { n = split(pods, list, "\n"); for (i = 1; i <= n; i++) if (list[i] != "") want[list[i]] = 1 }
        $0 ~ /^container_memory_working_set_bytes/ && index($0, "namespace=\"" ns "\"") {
          if (match($0, /pod="[^"]+"/)) {
            pod = substr($0, RSTART + 5, RLENGTH - 6)
            if (pod in want) total += $2
          }
        }
        END { printf "%d", total + 0 }'
}

kurly::_sample_memory() {
  local ns="$1" name="$2" out="$3" stop="$4" peak=0 now
  while [ ! -f "$stop" ]; do
    now="$(kurly::_pod_memory "$ns" "$name")"
    [ -n "$now" ] && [ "$now" -gt "$peak" ] 2>/dev/null && peak="$now"
    sleep 2
  done
  printf '%s' "$peak" >"$out"
}

# One record per stage, written the moment it is produced rather than collected
# at the end — a fleet walk that is killed half way keeps everything it measured.
kurly::_record_measurement() {
  local stage="$1" seconds="$2" peak="$3" steady="$4" key file
  # A workload that is Ready in nine seconds can finish before the kubelet
  # publishes a single sample, and the startup peak comes back as zero — the
  # catalogue would then say "needs 0Mi to start", which is the most confident
  # possible way to be wrong. The settled reading is a real reading of the same
  # containers, so it stands in when nothing was captured.
  #
  # ONLY WHEN NOTHING WAS CAPTURED. A peak BELOW the settled figure is a genuine
  # and common result — an application that is Ready before it has filled its
  # caches uses more once it is running than it did to start — and clamping the
  # two together would erase exactly the gap these two fields exist to show.
  [ "${peak:-0}" -gt 0 ] 2>/dev/null || peak="$steady"
  key="$(printf '%s' "$stage" | sed -E 's#workloads/([^/]+)/([^/]+)\.libsonnet#\1/\2#')"
  mkdir -p .build/measurements
  file=".build/measurements/$(printf '%s' "$key" | tr '/' '__').json"
  # The digest these numbers are ABOUT, recorded alongside them. A measurement
  # describes specific bits: the next image bump can change what a workload needs
  # to start, and carrying the old figure forward onto bits nobody ran would be
  # publishing a guess in a field whose whole claim is that it was measured.
  local digest=""
  if [ -f "${stage%.libsonnet}.image" ]; then
    digest="$(sed -E 's/.*@(sha256:[0-9a-f]+).*/\1/' "${stage%.libsonnet}.image")"
    case "$digest" in sha256:*) ;; *) digest="" ;; esac
  fi
  jq -n --arg key "$key" --arg d "$digest" --argjson s "$seconds" \
    --argjson p "${peak:-0}" --argjson st "${steady:-0}" \
    '{key: $key, digest: $d, secondsToReady: $s, peakStartupBytes: $p, steadyBytes: $st}' >"$file"
  echo "measured: ${key} ready in ${seconds}s, peak $((${peak:-0} / 1048576))Mi, steady $((${steady:-0} / 1048576))Mi"
}

kurly::boot() {
  local stage="$1" ns="$2" extra="${3:-}" params="${4:-}" manifests own
  manifests="$(kurly::render "$stage" "+ k.hostUsers() ${extra}" "$params")"
  # A CLUSTER ADD-ON names the namespace it belongs in, and `kubectl apply
  # --namespace` REFUSES an object that already declares a different one — the
  # whole apply fails with "does not match the namespace", before anything is
  # created. Its RBAC and its controller are written for that namespace, so the
  # answer is to boot it where it says, not to strip the field and relocate a
  # component whose ClusterRoleBinding still points at the original.
  own="$(printf '%s' "$manifests" | jq -r '[.items[].metadata.namespace // empty] | first // empty')"
  if [ -n "$own" ]; then
    echo "== ${stage} is a cluster add-on: booting in its own namespace ${own} =="
    ns="$own"
  fi
  kurly::namespace "$ns" >/dev/null
  echo "== boot ${stage} in ${ns} =="
  # The clock starts at the apply, not at the first Ready check: pulling the
  # image and provisioning the volume are part of what a workload costs to start,
  # and a number that excluded them would flatter every large image in the set.
  local started=$SECONDS
  printf '%s' "$manifests" | kubectl apply --namespace="$ns" --filename=-
  # The name label the workload stamps on its own objects, read off the render
  # rather than guessed from the directory: a stage may be called with a
  # different name, and measuring by a guessed label silently measures nothing.
  local own_name
  own_name="$(printf '%s' "$manifests" | jq -r '[.items[]
    | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet")
    | .metadata.labels["app.kubernetes.io/name"]] | map(select(. != null)) | first // empty')"
  local stopfile peakfile sampler
  stopfile="$(mktemp -u)"; peakfile="$(mktemp)"
  kurly::_sample_memory "$ns" "$own_name" "$peakfile" "$stopfile" &
  sampler=$!
  local ctrl found=0
  for ctrl in $(kubectl --namespace="$ns" get deployment,statefulset,daemonset --output=name 2>/dev/null); do
    found=1
    if ! kurly::await_ready "$ns" "$ctrl"; then
      touch "$stopfile"; wait "$sampler" 2>/dev/null || true; rm -f "$stopfile" "$peakfile"
      echo "::error::${stage}: ${ctrl} never became Ready"; kurly::diagnose "$ns"; return 1
    fi
  done
  local seconds=$((SECONDS - started)) peak steady
  touch "$stopfile"; wait "$sampler" 2>/dev/null || true
  peak="$(cat "$peakfile" 2>/dev/null || printf 0)"
  # Settle before reading steady state: a process that has just finished its
  # migrations is still holding what the migration needed, so a reading taken at
  # the moment of Ready is the startup peak under another name.
  sleep "${KURLY_MEASURE_SETTLE:-15}"
  steady="$(kurly::_pod_memory "$ns" "$own_name")"
  rm -f "$stopfile" "$peakfile"
  local cj
  for cj in $(kubectl --namespace="$ns" get cronjob --output=name 2>/dev/null); do
    found=1
    local job="smoke-${cj##*/}"
    kubectl --namespace="$ns" create job "$job" --from="$cj"
    kubectl --namespace="$ns" wait --for=condition=complete "job/${job}" --timeout=300s \
      || { echo "::error::${stage}: ${cj} test job did not complete"; kurly::diagnose "$ns"; return 1; }
  done
  [ "$found" = 1 ] || { echo "::error::${stage}: rendered no runnable controller"; return 1; }
  kurly::_record_measurement "$stage" "$seconds" "$peak" "$steady"
  echo "ok: ${stage} is healthy on a live cluster"
}

# A single shared test password every provisioned dependency and minted Secret
# uses, so an app's DB_PASSWORD Secret key matches the database it connects to.
# Complex enough for the apps that enforce a policy (an upper-case letter, a digit,
# and a symbol), and free of characters that would need escaping inside a URL.
KURLY_E2E_PASSWORD="Kurly-e2e-Passw0rd"

# Mints the Secret a stage reads, from the catalog's per-stage `secretKeys`
# contract: each key is generated as a password (the shared test password, so it
# matches the provisioned database), a fixed hex string, or its declared literal.
# kurly authors no Secret itself — a consumer supplies it — so the e2e supplies a
# throwaway one shaped exactly like the catalog says the app needs.
#   kurly::secret <ns> <secret-name> <stage-file>
kurly::secret() {
  local ns="$1" name="$2" stage="$3"
  local keys
  keys="$(jq -c --arg ip "github.com/metio/kurly/${stage}" \
    '.workloads[].stages[] | select(.importPath==$ip) | .secretKeys // []' .build/catalog.json)"
  [ "$keys" != "[]" ] && [ -n "$keys" ] || return 0
  # The workload id, so a connection-URL key can be built from the throwaway
  # postgres/valkey this app's deps were provisioned under (the <id>-db-rw /
  # <id>-cache-headless convention in kurly::provision_deps).
  local id; id="$(sed -E 's#^workloads/([^/]+)/.*#\1#' <<<"$stage")"
  local args=() k gen val
  while read -r k; do
    gen="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .generate' <<<"$keys")"
    case "$gen" in
      password) val="$KURLY_E2E_PASSWORD" ;;
      hex)
        # A random hex string of the DECLARED length — apps like Django reject a
        # short or low-entropy SECRET_KEY (security.W009), so honour the length.
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 64' <<<"$keys")"
        val="$(head -c "$len" /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c "1-${len}")"
        ;;
      # A base64 key of the declared BYTE length. Two alphabets, because apps
      # disagree: Fernet and the libraries wrapping it require the url-safe one,
      # while a Laravel APP_KEY is rejected unless it is standard base64.
      base64)
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 32' <<<"$keys")"
        val="$(head -c "$len" /dev/urandom | base64 | tr -d '\n')"
        ;;
      # Laravel's APP_KEY, which is base64 WITH the marker its own tooling writes
      # (`php artisan key:generate` produces base64:...). The prefix is what tells
      # Laravel to decode rather than take the string as raw key bytes, so a bare
      # base64 string of the right length is rejected — lychee's entrypoint says
      # "APP_KEY contains invalid base64 data" and Laravel itself, in frankenphp
      # worker mode, simply never reaches a request, which surfaces as the worker
      # failing to start rather than as anything about a key.
      laravelKey)
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 32' <<<"$keys")"
        val="base64:$(head -c "$len" /dev/urandom | base64 | tr -d '\n')"
        ;;
      base64url)
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 32' <<<"$keys")"
        val="$(head -c "$len" /dev/urandom | base64 | tr '+/' '-_' | tr -d '\n')"
        ;;
      literal) val="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .value' <<<"$keys")" ;;
      # Composite connection strings some apps read as a single secret (Prisma's
      # DATABASE_URL, etc.), built from the provisioned dependency.
      # The throwaway postgres serves plaintext, and a client that defaults to
      # sslmode=require (Go's pq, among others) fails its first query without this.
      postgresUrl) val="postgresql://${id}:${KURLY_E2E_PASSWORD}@${id}-db-rw:5432/${id}?sslmode=disable" ;;
      redisUrl) val="redis://:${KURLY_E2E_PASSWORD}@${id}-cache-headless:6379" ;;
      # The MySQL equivalent, for apps that take one connection string.
      mysqlUrl) val="mysql://${id}:${KURLY_E2E_PASSWORD}@${id}-db:3306/${id}" ;;
      # The MongoDB equivalent. NO CREDENTIALS in it, deliberately: the throwaway
      # mongo above starts without MONGO_INITDB_ROOT_USERNAME, so it enforces no
      # authentication and a URL carrying a user and password would be refused by
      # the very server this mints against. A real deployment supplies its own.
      #
      # Without this a MongoDB-backed workload cannot be proven at all — its
      # endpoint falls back to the bare password, the app reads that as a
      # connection string, and it fails with something like "connect to database
      # at null" that says nothing about the missing generator.
      mongoUrl) val="mongodb://${id}-db:27017/${id}" ;;
      *) val="$KURLY_E2E_PASSWORD" ;;
    esac
    args+=("--from-literal=${k}=${val}")
  done < <(jq -r '.[].key' <<<"$keys")
  kubectl --namespace="$ns" create secret generic "$name" "${args[@]}" \
    --dry-run=client --output=yaml | kubectl apply --filename=-
}

# A throwaway PostgreSQL for an app's e2e: a single Deployment + Service at the
# service name the app defaults to (so it connects with no param override), seeded
# with the app's database, user, and the shared test password. Not hardened (it is
# a disposable dependency, torn down with the cluster), so it boots on kind's
# default posture without relaxation. Extra "-c name=value" server settings and a
# custom image (e.g. one carrying an extension) may be passed as $5 / $6.
#   kurly::postgres <ns> <service> <db> <user> [image] [extraArgs]
# What provision_deps last stood up, so kurly::verify_database can ask that server
# whether the workload ever used it. Empty when the workload needs no database.
KURLY_DB_ENGINE="" KURLY_DB_SVC="" KURLY_DB_NAME="" KURLY_DB_USER=""
# The count verify_database read, for the caller to write to the ledger.
# shellcheck disable=SC2034  # consumed by hack/smoke/deep-run.sh
KURLY_DB_TABLES=""

# Asks the provisioned database how many tables the workload created in it.
#
# This is the check whose absence made `delivered` weaker than it reads. A rollout
# proves the pipeline; it does not prove the app could use its database, because a
# readiness probe that never issues a query cannot tell the two apart. Four
# workloads passed the walk against a database they could not use — bugsink and
# davis on the wrong engine, piwigo and baikal on a PostgreSQL neither supports.
# The app's own schema is the evidence: tables exist because the software created
# them, which is the software doing the thing rather than prose about it.
#
# An empty schema is not proof of a broken workload: wordpress and prestashop
# create no tables until somebody completes the web installer, so zero is correct
# for them and damning almost everywhere else. No absolute threshold separates
# those, but the workload's OWN LAST READING does — a count that was positive and
# is now zero is a regression whatever the app's installer does. So this compares
# against catalog/database-use.libsonnet and reports:
#
#   was positive, now zero  -> an error, and the caller says so
#   zero then, zero now     -> quiet, and nobody had to know about the installer
#   no previous reading     -> a warning, until the walk gives it one
#
# The count is left in KURLY_DB_TABLES for the caller to record.
kurly::verify_database() {
  local ns="$1" id="$2" tables="" prior=""
  KURLY_DB_TABLES=""
  [ -n "$KURLY_DB_ENGINE" ] || return 0
  case "$KURLY_DB_ENGINE" in
    postgres)
      tables="$(kubectl exec --namespace="$ns" "deployment/${KURLY_DB_SVC}" -- \
        psql -U "$KURLY_DB_USER" -d "$KURLY_DB_NAME" -tAc \
        "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema')" \
        2>/dev/null || true)"
      ;;
    mysql)
      # The image is mariadb, which ships the client as `mariadb`; `mysql` is not
      # on its PATH at all, so naming it directly reports every workload as
      # unreadable rather than as unmeasured.
      tables="$(kubectl exec --namespace="$ns" "deployment/${KURLY_DB_SVC}" -- sh -c \
        "c=\$(command -v mariadb || command -v mysql) && \"\$c\" -u'${KURLY_DB_USER}' -p'${KURLY_E2E_PASSWORD}' -N -B -e \"select count(*) from information_schema.tables where table_schema='${KURLY_DB_NAME}'\"" \
        2>/dev/null || true)"
      ;;
  esac
  tables="$(printf '%s' "$tables" | tr -dc '0-9')"
  if [ -z "$tables" ]; then
    echo "::warning::${id}: could not read its ${KURLY_DB_ENGINE} schema — database use UNKNOWN"
    return 0
  fi
  # shellcheck disable=SC2034  # consumed by hack/smoke/deep-run.sh
  KURLY_DB_TABLES="$tables"
  prior="$(grep -oE "^  '?${id}'?: \{ tables: [0-9]+" catalog/database-use.libsonnet 2>/dev/null \
    | grep -oE '[0-9]+$' || true)"
  if [ "$tables" -gt 0 ]; then
    echo "== ${id}: ${tables} tables in its ${KURLY_DB_ENGINE} — the app used its database =="
  elif [ -z "$prior" ]; then
    echo "::warning::${id}: rolled out, but its ${KURLY_DB_ENGINE} holds NO tables and there is no earlier reading to compare — it either never reached the database or waits for an installer"
  elif [ "$prior" -gt 0 ]; then
    echo "::error::${id}: wrote ${prior} tables to its ${KURLY_DB_ENGINE} on the last walk and none on this one — a regression, whatever its installer does"
    return 1
  fi
  return 0
}

# Was anything in this namespace killed for exceeding its memory limit, and at what
# limit? Sets KURLY_OOM_AT to that limit when so, empty otherwise.
#
# Only an OOMKill counts. A workload that merely failed says nothing about
# resources — the walk has failed workloads for being handed the wrong database, for
# an installer lock, inside an init script, and because a git rebase moved the tree
# underneath them — and recording those as evidence of a memory floor would invent
# exactly the sort of number this repository keeps deleting. The kernel killing a
# container for exceeding its limit is a resource fact; a failure is not.
#
# Both states are read: `state` catches the container sitting dead right now,
# `lastState` the one that was killed and restarted, which is the usual shape by the
# time a crash-looping pod is looked at.
kurly::detect_oom() {
  local ns="$1" id="$2" pods p limit=""
  KURLY_OOM_AT=""
  pods="$(kubectl --namespace="$ns" get pods -o name 2>/dev/null || true)"
  [ -n "$pods" ] || return 0
  for p in $pods; do
    # The workload's own pods only: a provisioned database OOMing is a fact about
    # the harness's throwaway server, not about the workload under test.
    case "${p#pod/}" in
      "${id}"-db*|"${id}"-cache*) continue ;;
      "${id}"*) : ;;
      *) continue ;;
    esac
    if kubectl --namespace="$ns" get "$p" \
         -o jsonpath='{.status.containerStatuses[*].state.terminated.reason}{" "}{.status.containerStatuses[*].lastState.terminated.reason}' 2>/dev/null \
         | grep -q OOMKilled; then
      limit="$(kubectl --namespace="$ns" get "$p" \
        -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null || true)"
      KURLY_OOM_AT="${limit:-unset}"
      echo "::warning::${id}: OOMKilled at a memory limit of ${KURLY_OOM_AT} — it needs more than that, which is a floor with evidence behind it"
      return 0
    fi
  done
  return 0
}

kurly::postgres() {
  local ns="$1" svc="$2" db="$3" user="$4" image="${5:-docker.io/library/postgres:17}" extra="${6:-}"
  echo "== provision postgres ${svc} (db=${db}, user=${user}) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: postgres
          image: ${image}
          args: ["postgres"${extra:+, ${extra}}]
          env:
            - { name: POSTGRES_DB, value: "${db}" }
            - { name: POSTGRES_USER, value: "${user}" }
            - { name: POSTGRES_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            - { name: PGDATA, value: /var/lib/postgresql/data/pgdata }
          ports: [{ containerPort: 5432 }]
          # Rollout completion alone says only that the process started; an app that
          # connects once and exits (rather than retrying) races it without this.
          readinessProbe:
            exec: { command: ["pg_isready", "-U", "${user}", "-d", "${db}"] }
            periodSeconds: 2
            failureThreshold: 30
          volumeMounts: [{ name: data, mountPath: /var/lib/postgresql/data }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
  # A workload written for CloudNativePG reads its credentials from the operator's
  # generated `<cluster>-app` Secret rather than from its own; the throwaway server
  # stands in for the cluster, so publish the same Secret under the same name.
  local cluster="${svc%-rw}"
  kubectl --namespace="$ns" create secret generic "${cluster}-app" \
    --from-literal=username="$user" \
    --from-literal=password="$KURLY_E2E_PASSWORD" \
    --from-literal=dbname="$db" \
    --from-literal=host="$svc" \
    --from-literal=port=5432 \
    --from-literal=uri="postgresql://${user}:${KURLY_E2E_PASSWORD}@${svc}:5432/${db}?sslmode=disable" \
    --dry-run=client --output=yaml | kubectl apply --filename=-
}

# A throwaway Valkey (Redis) for an app's e2e, at the service name the app
# defaults to. Authless (matches the app defaulting to no REDIS_PASSWORD).
#   kurly::cache <ns> <service>
kurly::cache() {
  # An app whose queue library cannot send AUTH (bigcapital's) passes an empty
  # password to get an open server.
  local ns="$1" svc="$2" password="${3-$KURLY_E2E_PASSWORD}"
  echo "== provision valkey ${svc} =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: valkey
          image: docker.io/valkey/valkey:8
          # Password-protected, because an app given a REDIS_PASSWORD sends AUTH —
          # which a server without one rejects outright.
          args: ["valkey-server"${password:+, "--requirepass", "${password}"}]
          ports: [{ containerPort: 6379 }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 6379, targetPort: 6379 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# A throwaway InfluxDB 2.x for an app's e2e, at the service name the app defaults
# to, with its organization, bucket and an admin token already set up by the
# image's own setup mode — an app that writes metrics on startup cannot wait for
# a human to click through the onboarding form.
#
# NOT a carried workload, and deliberately so: influxdb is in
# catalog/excluded.libsonnet because its upstream sells hosting, which is a rule
# about what this catalogue offers to HOST for somebody. It says nothing about
# standing one up for ninety seconds to prove that an application which needs one
# actually starts.
#   kurly::influxdb <ns> <service> <org> <bucket> <token>
kurly::influxdb() {
  local ns="$1" svc="$2" org="$3" bucket="$4" token="$5"
  echo "== provision influxdb ${svc} (org=${org}, bucket=${bucket}) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: influxdb
          image: docker.io/library/influxdb:2.7
          env:
            - { name: DOCKER_INFLUXDB_INIT_MODE, value: setup }
            - { name: DOCKER_INFLUXDB_INIT_USERNAME, value: kurly }
            - { name: DOCKER_INFLUXDB_INIT_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            - { name: DOCKER_INFLUXDB_INIT_ORG, value: "${org}" }
            - { name: DOCKER_INFLUXDB_INIT_BUCKET, value: "${bucket}" }
            - { name: DOCKER_INFLUXDB_INIT_ADMIN_TOKEN, value: "${token}" }
          ports: [{ containerPort: 8086 }]
          # Setup runs before the HTTP listener answers, and an app that writes
          # its first point immediately would otherwise meet a closed port.
          readinessProbe:
            httpGet: { path: /health, port: 8086 }
            periodSeconds: 3
            failureThreshold: 40
          volumeMounts: [{ name: data, mountPath: /var/lib/influxdb2 }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 8086, targetPort: 8086 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# A throwaway MariaDB for an app's e2e, at the service name the app defaults to,
# seeded with the app's database, user, and the shared test password (and the
# same password for root). Many self-hosted apps need MySQL/MariaDB rather than
# PostgreSQL.
#   kurly::mysql <ns> <service> <db> <user>
# A throwaway MongoDB for an app's e2e: a single Deployment + Service at the
# service name the app defaults to. Unauthenticated, like the other disposable
# dependencies — an app that also wants credentials passes them in its own URL.
#   kurly::mongodb <ns> <service>
# A throwaway S3-compatible object store for an app's e2e: kurly's own seaweedfs
# workload, which serves its S3 gateway on :8333 with anonymous access, plus the
# bucket the app expects. The Service it creates is HEADLESS, so the endpoint is
# http://seaweedfs-headless.<ns>.svc:8333 — there is no `seaweedfs` Service, and
# this comment said there was until a consumer was pointed at it and got nothing.
# An app that also wants credentials is given dummy ones, which seaweedfs ignores
# in this mode.
#   kurly::objectstorage <ns> <bucket>
kurly::objectstorage() {
  local ns="$1" bucket="$2"
  echo "== provision seaweedfs S3 (bucket=${bucket}) =="
  kurly::render workloads/seaweedfs/server.libsonnet "+ k.hostUsers()" \
    | kubectl apply --namespace="$ns" --filename=-
  kubectl --namespace="$ns" rollout status statefulset/seaweedfs --timeout=300s
  # Creating a bucket is a plain PUT against the gateway, so no client image with
  # an S3 SDK is needed.
  kubectl --namespace="$ns" run s3-init --rm --attach --restart=Never \
    --image=docker.io/curlimages/curl:8.21.0 --command -- \
    curl -sf -X PUT "http://seaweedfs-0.seaweedfs-headless.${ns}.svc:8333/${bucket}" >/dev/null
}

# ALWAYS A REPLICA SET, even of one member. An application that reads the oplog —
# Rocket.Chat is the one here, and it is not unusual — cannot use a standalone
# server at all: the oplog is a replication artefact and a standalone mongod does
# not keep one. Such an app fails at startup against a server that is otherwise
# working perfectly, which reads as the application being broken.
#
# A single-member set costs nothing for the applications that do not care: the
# connection string works unchanged with or without `?replicaSet=`, so there is
# no reason to offer two shapes and pick between them.
#
# The set has to be INITIATED before mongod serves anything, and `rs.initiate()`
# is what turns a started process into a usable one — a probe that only checks
# the port is open reports ready while every query still fails with
# NotYetInitialized.
kurly::mongodb() {
  local ns="$1" svc="$2"
  echo "== provision mongodb ${svc} (replica set rs0) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: mongodb
          image: docker.io/library/mongo:8
          # --bind_ip_all because a replica-set member advertises the host it was
          # initiated with, and the default binding would refuse the connection
          # that arrives on the Service address.
          args: ["--replSet", "rs0", "--bind_ip_all"]
          ports: [{ containerPort: 27017 }]
          readinessProbe:
            # The set must ANSWER, not merely listen: hello().isWritablePrimary
            # is false until the member has been initiated and elected itself, so
            # this is what distinguishes a usable server from a started one.
            exec:
              command: ["mongosh", "--quiet", "--eval", "db.hello().isWritablePrimary"]
            periodSeconds: 3
            failureThreshold: 40
          volumeMounts: [{ name: data, mountPath: /data/db }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 27017, targetPort: 27017 }]
EOF
  # Initiate BEFORE waiting for the rollout: the readiness probe above only
  # passes once the set is live, so waiting first would time out every time.
  # `host` names the member as the Service, which is the address every client
  # reaches it at — a member initiated as its pod IP hands that IP back to the
  # client on connect, and the pod IP changes on every restart.
  local pod
  for _ in $(seq 1 60); do
    pod="$(kubectl --namespace="$ns" get pod -l "app=${svc}" -o name 2>/dev/null | head -1)"
    [ -n "$pod" ] && kubectl --namespace="$ns" exec "$pod" -- mongosh --quiet --eval \
      "try { rs.status().ok } catch (e) { rs.initiate({_id:'rs0',members:[{_id:0,host:'${svc}:27017'}]}) }" >/dev/null 2>&1 && break
    sleep 2
  done
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=240s
}

# A throwaway single-node Elasticsearch, for the workloads that index into one.
#
# security.enabled=false, which a production cluster must never do: the point
# here is that a scenario proves the WORKLOAD starts and talks to its search
# backend, and making it also negotiate TLS and a bootstrap password proves
# something about Elasticsearch instead. A stage that needs credentials still
# gets them from its own Secret.
#
# discovery.type=single-node, or the node waits for peers that will never come
# and never reports ready. -Xms/-Xmx are pinned low because the default heap is
# half of the NODE's memory, which on a laptop-sized kind node is enough to get
# the pod OOM-killed while it is still starting.
kurly::elasticsearch() {
  local ns="$1" svc="$2"
  # The probe authenticates like any client would; base64 of elastic:<password>.
  local esauth
  esauth="$(printf 'elastic:%s' "$KURLY_E2E_PASSWORD" | base64 -w0)"
  echo "== provision elasticsearch ${svc} =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: elasticsearch
          image: docker.io/library/elasticsearch:8.19.7
          env:
            - { name: discovery.type, value: single-node }
            # Security ON, with the password every other provisioner here mints.
            # A workload that indexes into Elasticsearch sends credentials —
            # ELASTIC_PASSWORD is in its Secret — and against a server with
            # security disabled those credentials are not rejected so much as
            # unanswerable: the app retries "waiting for ES" while the cluster
            # sits green, which reads as unreachable and is a disagreement about
            # authentication.
            - { name: xpack.security.enabled, value: "true" }
            - { name: ELASTIC_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            # A snapshot repository path, which Elasticsearch refuses to register
            # one without. An app that backs its index up checks for it at start
            # and stops: tube-archivist prints "path.repo env var not found. set
            # the following env var to the ES container" and exits — a complaint
            # about THIS server, phrased as if the reader were configuring it,
            # which reads as the workload's own misconfiguration. It points at the
            # data directory, so a snapshot lands on the same throwaway volume.
            - { name: path.repo, value: /usr/share/elasticsearch/data/snapshot }
            - { name: ES_JAVA_OPTS, value: "-Xms512m -Xmx512m" }
          ports: [{ containerPort: 9200 }]
          readinessProbe:
            httpGet:
              path: /_cluster/health
              port: 9200
              httpHeaders:
                - { name: Authorization, value: "Basic ${esauth}" }
            periodSeconds: 5
            failureThreshold: 60
          volumeMounts: [{ name: data, mountPath: /usr/share/elasticsearch/data }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 9200, targetPort: 9200 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=300s
}

kurly::mysql() {
  local ns="$1" svc="$2" db="$3" user="$4"
  echo "== provision mariadb ${svc} (db=${db}, user=${user}) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: mariadb
          image: docker.io/library/mariadb:11
          env:
            - { name: MARIADB_ROOT_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            - { name: MARIADB_DATABASE, value: "${db}" }
            - { name: MARIADB_USER, value: "${user}" }
            - { name: MARIADB_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
          ports: [{ containerPort: 3306 }]
          # The entrypoint initializes the data directory behind a TEMPORARY
          # server bound to a socket, then restarts for real — so a pod that is
          # Running is not a database that answers, and rollout status alone
          # returns while it still refuses connections. An app that connects
          # once at startup and exits on failure loses that race and crashloops
          # for a reason that has nothing to do with the app. The probe is
          # mariadb's own, and --innodb_initialized is what distinguishes the
          # real server from the init-time one.
          readinessProbe:
            exec: { command: ["healthcheck.sh", "--connect", "--innodb_initialized"] }
            periodSeconds: 3
            failureThreshold: 40
          volumeMounts: [{ name: data, mountPath: /var/lib/mysql }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 3306, targetPort: 3306 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# Fast check for an operator/custom-resource workload (no image of its own): it
# installs the operator's CRDs and validates the rendered custom resource against
# the real schema with a server-side dry-run — catching a version or field the
# operator would reject, in seconds, without waiting for a full cluster to
# reconcile. Standing up the real database/search/identity cluster is the deeper
# tier that comes later; this is the fast "is this version's manifest broken"
# signal the auto-merge net needs.
#   kurly::validate_cr <ns> <stage-file> <crd-url>...
kurly::validate_cr() {
  local ns="$1" stage="$2"; shift 2
  local url names attempt
  for url in "$@"; do
    echo "== install CRD ${url##*/} =="
    mapfile -t names < <(kubectl apply --server-side --force-conflicts --filename="$url" --output=name)
    printf '%s\n' "${names[@]}"
    # A freshly applied CRD is not servable until the apiserver establishes it, so a
    # dry-run right after the apply fails with "no matches for kind".
    [ "${#names[@]}" -gt 0 ] \
      && kubectl wait --for=condition=Established --timeout=120s "${names[@]}" >/dev/null 2>&1
  done
  # kubectl caches discovery per cluster; drop it so the new group is visible.
  rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true
  kurly::namespace "$ns" >/dev/null
  echo "== validate the rendered custom resource against the operator schema =="
  for attempt in 1 2 3 4 5; do
    if kurly::render "$stage" \
      | kubectl apply --namespace="$ns" --server-side --dry-run=server --filename=-; then
      echo "ok: ${stage} validates against the operator schema on a live cluster"
      return 0
    fi
    echo "validate attempt ${attempt} failed — retrying"
    sleep 5
  done
  echo "::error::${stage}: the custom resource was rejected by the operator schema"
  return 1
}

# Frees everything a workload's fast + deep checks created, so the shared single
# cluster does not accumulate pods across the walk. Deletes the workload's
# namespaces (kurly-<id>, kurly-<id>-<stage>, kurly-deep-<id>) and the deep
# check's cluster-scoped RoleBinding, then waits briefly for termination so the
# next workload starts on a drained cluster. Best-effort — a slow finalizer never
# fails the run. Installed operators/CRDs are left in place (harmless, and
# re-running their install is idempotent).
kurly::cleanup_workload() {
  local id="$1" nss
  mapfile -t nss < <(kubectl get namespace --output=name 2>/dev/null \
    | sed 's#namespace/##' | grep -E "^kurly-(deep-)?${id}(-|\$)" || true)
  # --interactive=false: kubectl prompts for delete confirmation and reads EOF as
  # "no" in a non-interactive shell, silently cancelling the delete otherwise.
  kubectl delete clusterrolebinding "stageset-deployer-kurly-deep-${id}" --interactive=false --ignore-not-found >/dev/null 2>&1 || true
  # Cluster-scoped objects outlive the namespace, and a workload that ships
  # admission policies (bollwerk) would keep enforcing them over every workload
  # booted afterwards on this shared cluster. Everything kurly renders carries the
  # managed-by label, so the sweep is precise.
  local kind
  for kind in validatingadmissionpolicybinding validatingadmissionpolicy \
    mutatingwebhookconfiguration validatingwebhookconfiguration apiservice \
    clusterrolebinding clusterrole priorityclass ingressclass storageclass; do
    kubectl delete "$kind" --selector=app.kubernetes.io/managed-by=kurly \
      --interactive=false --ignore-not-found >/dev/null 2>&1 || true
  done
  # A cluster add-on states its own namespace (kube-system, opencost, spegel …), so
  # its objects survive the kurly-<id> namespace sweep. A left-behind APIService with
  # no healthy backend breaks discovery — and with it the deletion of EVERY
  # namespace, poisoning the rest of the walk.
  kubectl delete deployment,daemonset,service,serviceaccount --all-namespaces \
    --selector="app.kubernetes.io/managed-by=kurly,app.kubernetes.io/name=${id}" \
    --interactive=false --ignore-not-found >/dev/null 2>&1 || true
  [ "${#nss[@]}" -gt 0 ] || return 0
  echo "== cleanup ${id}: deleting namespaces ${nss[*]} =="
  # A blocking delete (kubectl's default --wait) returns only once the namespaces
  # and everything in them are gone, so the next workload starts on a drained
  # cluster; the timeout caps a stuck finalizer rather than hanging the walk.
  kubectl delete namespace "${nss[@]}" --interactive=false --timeout=180s >/dev/null 2>&1 || true
}

# Extracts a stage parameter's simple quoted default (dbHost='x' -> x); empty when
# the default is a computed expression rather than a literal.
kurly::_param() { grep -oE "^[[:space:]]*$2='[^']*'" "$1" 2>/dev/null | head -1 | sed -E "s/.*='([^']*)'.*/\1/" || true; }

# The workloads a PR changed relative to the default branch — one per line. On a
# manual dispatch (no base to diff), or when $WORKLOADS is set explicitly, that
# selection wins instead. This is what keeps the single pipeline short: only
# changed workloads run.
kurly::changed_workloads() {
  if [ -n "${WORKLOADS:-}" ]; then
    printf '%s\n' $WORKLOADS
    return 0
  fi
  local base="origin/${BASE_REF:-main}"
  git diff --name-only "$base"...HEAD 2>/dev/null \
    | grep -oE '^workloads/[a-z0-9-]+/' | sed -E 's#workloads/([^/]+)/#\1#' | sort -u
}

# Provisions a workload's declared dependencies + Secret into <ns>, reading the
# catalog and the stage's default connection params at runtime — the same wiring
# the generated fast scenario bakes in, reusable by the deep check.
# Sets up whatever a workload needs BEYOND a database, a cache and a Secret minted
# from the catalogue's secretKeys — a configuration Secret the operator authors, a
# volume several stages share, an operator that must exist first.
#
# It lives in one file per workload, hack/smoke/prereq/<id>.sh, run with $ns set,
# because BOTH tiers need it and they were drifting: the fast scenarios carried
# this setup inline, the deep check had no equivalent, and every workload with a
# prerequisite failed the deep check for want of scaffolding rather than for
# anything wrong with it. A workload with no prerequisites has no file and this is
# a no-op.
#
#   kurly::prereq dex kurly-deep-dex
kurly::prereq() {
  local id="$1" ns="$2"
  # A separate statement: within ONE `local`, $id is not yet assigned when $f is
  # evaluated, and under `set -u` that is fatal rather than merely empty.
  local f="hack/smoke/prereq/${id}.sh"
  [ -f "$f" ] || return 0
  echo "== prerequisites for ${id} in ${ns} =="
  # A subshell so a prerequisite cannot leak variables into the caller, and
  # sourced rather than executed so it can use the helpers in this file.
  (
    set -euo pipefail
    # $ns is a local of this function and the subshell inherits it, which is how
    # the sourced file addresses the namespace.
    # shellcheck source=/dev/null
    source "$f"
  )
}

kurly::provision_deps() {
  local id="$1" ns="$2" primary st f dbHost dbName dbUser redisHost secretName dbEngine wantsSql
  # Cleared per workload: these are globals so the post-delivery check can read
  # them, and a workload needing no database must not inherit the last one's.
  KURLY_DB_ENGINE="" KURLY_DB_SVC="" KURLY_DB_NAME="" KURLY_DB_USER=""
  primary="workloads/${id}/$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|.stages[0].id' .build/catalog.json).libsonnet"
  if [ "$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|if ((.requires//[])|map(select(.kind=="database"))|length)>0 then 1 else 0 end' .build/catalog.json)" = 1 ]; then
    wantsSql=true
    # A workload whose Secret is keyed MONGO_URL does not want a SQL server at all.
    # The catalogue records only `database: required` — it has no engine field yet —
    # so the classifier below, which knows two engines, was standing up a PostgreSQL
    # for it. rocketchat then failed in its Mongo driver, having been given a
    # database it never asked for, and the schema probe would have read the untouched
    # PostgreSQL as zero tables and called it a workload that ignored its database.
    #
    # MongoDB does not run on this host at all (SERVER-121912 against this kernel),
    # so there is nothing to provision instead. Saying so beats provisioning the
    # wrong thing silently: the workload still fails, but for a reason that is true.
    # Read from the catalogue's secretKeys where they exist, and from the stage
    # otherwise. wekan wants MONGO_URL and declares NO secretKeys at all, so a
    # catalogue-only check missed it and it was handed a PostgreSQL like rocketchat.
    #
    # A DECLARED SQL URL WINS over either, and that is not a tie-break for its own
    # sake: ferretdb speaks the MongoDB protocol while STORING in PostgreSQL. Its
    # stage mentions Mongo throughout and its secretKeys say FERRETDB_POSTGRESQL_URL
    # with a postgresUrl generator, and it has delivered against a PostgreSQL. A
    # check that read the protocol would take its database away.
    if [ -z "$(jq -r --arg id "$id" '[.workloads[]|select(.id==$id)|.stages[]?|.secretKeys//[]|.[]|.generate]|map(select(test("(postgres|mysql)Url")))|join(",")' .build/catalog.json)" ] \
       && { jq -e --arg id "$id" '.workloads[]|select(.id==$id)|[.stages[]?.secretKeys//[]|.[]|.key]|any(test("MONGO"))' .build/catalog.json >/dev/null 2>&1 \
            || grep -qE 'MONGO_URL|MONGODB_URI|mongodb-cluster' "$primary" 2>/dev/null; }; then
      echo "::warning::${id}: its Secret is keyed MONGO_*, so it wants MongoDB — provisioning no SQL server, and MongoDB cannot run on this host"
      wantsSql=false
    fi
    if [ "$wantsSql" = true ]; then
    dbName="$(kurly::_param "$primary" dbName)"; [ -n "$dbName" ] || dbName="$(kurly::_param "$primary" database)"; [ -n "$dbName" ] || dbName="$id"
    dbUser="$(kurly::_param "$primary" dbUser)"; [ -n "$dbUser" ] || dbUser="$id"
    # Which engine, in order of how much the answer is worth:
    #
    #   0. a dbEngine stated for this workload in hack/smoke/extra.json. Somebody
    #      established it, usually the hard way, and nothing below may overrule it.
    #   1. the catalogue's secretKeys generator. postgresUrl/mysqlUrl is somebody
    #      stating what the app connects to, which beats anything inferred —
    #      photoview declares postgresUrl, was handed a MySQL by the rule below,
    #      and died reporting "Utilizing postgres database driver".
    #   2. otherwise the stage source mentioning mysql/mariadb/3306, COMMENTS
    #      INCLUDED and CASE-SENSITIVELY. Both of those look like bugs and only one
    #      is. Reading prose is unpleasant and kept: 28 of the 37 workloads this
    #      rule classifies match only in a comment, and 21 of those have delivered
    #      against a MySQL.
    #
    #      The case-sensitivity is what sent prestashop a PostgreSQL — its header
    #      says "MySQL", capitalised, so the match failed and it fell through to
    #      the default and spent its whole life logging "Waiting for confirmation
    #      of MySQL service startup". Matching case-insensitively fixes prestashop
    #      and breaks nine others: gitea, nextcloud, drupal, vikunja, freshrss and
    #      friends mention MySQL as an ALTERNATIVE they support, run perfectly well
    #      on PostgreSQL, and have already delivered on one. So the bug stays, and
    #      the workloads it misclassifies get rule 0 instead.
    #
    # This is inference. Rules 0 and 1 are the only parts anyone wrote on purpose,
    # and the annotated engine of requires-v2 is meant to replace the rest.
    local declared engineOverride
    engineOverride="$(jq -r --arg k "${id}/${st:-}" --arg id "$id" '(.[$k] // .[$id] // {}).dbEngine // ""' hack/smoke/extra.json 2>/dev/null || true)"
    declared="$(jq -r --arg id "$id" '[.workloads[]|select(.id==$id)|.stages[]?|.secretKeys//[]|.[]|.generate]|map(select(test("Url$")))|join(",")' .build/catalog.json)"
    if [ -n "$engineOverride" ]; then
      dbEngine="$engineOverride"
    elif [[ "$declared" == *mysqlUrl* ]]; then
      dbEngine=mysql
    elif [[ "$declared" == *postgresUrl* ]]; then
      dbEngine=postgres
    elif grep -qE "3306|mariadb|mysql" "$primary" 2>/dev/null; then
      dbEngine=mysql
    else
      dbEngine=postgres
    fi
    KURLY_DB_ENGINE="$dbEngine" KURLY_DB_NAME="$dbName" KURLY_DB_USER="$dbUser"
    if [ "$dbEngine" = mysql ]; then
      dbHost="$(kurly::_param "$primary" dbHost)"; [ -n "$dbHost" ] || dbHost="${id}-db"
      KURLY_DB_SVC="$dbHost"
      kurly::mysql "$ns" "$dbHost" "$dbName" "$dbUser"
    else
      dbHost="$(kurly::_param "$primary" dbHost)"; [ -n "$dbHost" ] || dbHost="${id}-db-rw"
      KURLY_DB_SVC="$dbHost"
      # A workload that needs a PostgreSQL EXTENSION needs a server that ships it:
      # the stock image fails the app's first CREATE EXTENSION, and immich does not
      # merely warn — it crash-loops with DB_VECTOR_EXTENSION=vectorchord against a
      # server that has never heard of it. VectorChord additionally has to be
      # preloaded, so it is a shared_preload_libraries argument rather than only an
      # image swap.
      #
      # The same rule is emitted by gen-smoke for the fast scenarios; this is the
      # deep path, which had no equivalent and so provisioned a stock server for
      # the one workload in the catalogue that cannot use one.
      case "$(jq -r --arg id "$id" '[.workloads[]|select(.id==$id)|.requires[]?|select(.kind=="database")|.extensions//[]|.[]]|join(",")' .build/catalog.json)" in
        *vchord*)
          kurly::postgres "$ns" "$dbHost" "$dbName" "$dbUser" \
            ghcr.io/immich-app/postgres:17-vectorchord0.4.3-pgvector0.8.1-pgvectors0.3.0 \
            '"-c", "shared_preload_libraries=vchord.so"'
          ;;
        # pgvector, after vchord because that image already carries it.
        *vector*) kurly::postgres "$ns" "$dbHost" "$dbName" "$dbUser" docker.io/pgvector/pgvector:pg17 ;;
        *postgis*) kurly::postgres "$ns" "$dbHost" "$dbName" "$dbUser" docker.io/postgis/postgis:17-3.5 ;;
        *) kurly::postgres "$ns" "$dbHost" "$dbName" "$dbUser" ;;
      esac
    fi
    fi
  fi
  # An S3-compatible store where the catalogue says one is REQUIRED. kurly::objectstorage
  # has existed all along and nothing called it, so every workload that cannot run
  # without object storage was being asked to run without it — thanos-store crash-looped
  # against a bucket endpoint that resolved to nothing at all.
  #
  # `required` only. Twenty-one further workloads call it OPTIONAL, and standing up a
  # seaweedfs for each would add a StatefulSet and a rollout wait to a walk that already
  # takes a day, to exercise a path those workloads are explicitly able to skip.
  if [ "$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|if ((.requires//[])|map(select(.kind=="objectStorage" and .required))|length)>0 then 1 else 0 end' .build/catalog.json)" = 1 ]; then
    kurly::objectstorage "$ns" "$id"
  fi
  if [ "$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|if ((.requires//[])|map(select(.kind=="cache"))|length)>0 then 1 else 0 end' .build/catalog.json)" = 1 ]; then
    redisHost="$(kurly::_param "$primary" redisHost)"; [ -n "$redisHost" ] || redisHost="${id}-cache-headless"
    # Provision the cache the way the workload actually connects to it. Most take a
    # host and no credential, which is how a cache in the workload's OWN namespace
    # is normally run — it is reachable only from that namespace, and a
    # NetworkPolicy is the thing keeping it that way rather than a password. A few
    # read a full connection URL from their Secret, and the catalog's redisUrl
    # generator puts a password in it, so those need a server that expects one.
    #
    # Getting this backwards fails in both directions: an app with no credential
    # meets NOAUTH, and an app sending one meets "Client sent AUTH, but no password
    # is set". So it is read from the catalog per workload rather than defaulted.
    if jq -e --arg id "$id" '.workloads[]|select(.id==$id)|.stages[]|.secretKeys//[]|.[]|select(.generate=="redisUrl")' .build/catalog.json >/dev/null 2>&1; then
      kurly::cache "$ns" "$redisHost"
    else
      kurly::cache "$ns" "$redisHost" ""
    fi
  fi
  for st in $(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|.stages[].id' .build/catalog.json); do
    f="workloads/${id}/${st}.libsonnet"
    secretName="$(kurly::_param "$f" secretName)"; [ -n "$secretName" ] || secretName="$id"
    kurly::secret "$ns" "$secretName" "$f"
  done
}

# Deep check: deliver a workload through the real production path — build + push
# its source image, let Flux pull it (OCIRepository), JaaS render it
# (JsonnetSnippet), and stageset-controller apply it (StageSet) — then wait for
# its controllers to roll out. The flux/jaas/stageset stack (latest of each) and
# the kurly library image are installed/published once by the pipeline before the
# loop. A custom-resource workload has no controller of its own, so it is
# fast-check only and this is a no-op.
kurly::deep() {
  local id="$1"
  # A separate statement, because within ONE `local` the earlier assignment is not
  # in effect yet. This worked only by accident: deep-run.sh's loop variable is
  # also called id, so ${id} resolved to that global and happened to hold the same
  # value. Called from anywhere without such a global it fails on an unbound
  # variable instead.
  local ns="kurly-deep-${id}"
  local st f snip ctrl kind name apiv version versionBlock ex
  local clusterScoped ctrlNs nsRewrite params
  # Skip workloads whose stages render only a custom resource (no controller).
  #
  # The render is run and JUDGED SEPARATELY from the search for a controller,
  # because the two failures look identical when they are folded together and mean
  # opposite things. Piping a failed render into jq yields no match, which reads as
  # "this workload is operator-backed" — a notice, not an error, and the walk moves
  # on. Started outside the devShell, where jsonnet is not on PATH, that misreports
  # EVERY remaining workload as CR-only: 79 of them in one run, in about eight
  # seconds each, recording nothing and reporting no failure.
  # Rendered with NOTHING composed onto it. A custom-resource stage refuses a kurly
  # feature by design — "kurly features do not apply to a custom resource" — so
  # composing one here made the render fail for exactly the workloads this is meant
  # to identify. That produced the right outcome by the wrong route, and the route
  # is what matters: a failed render and a stage with no controller became the same
  # observation, so a genuinely broken render was indistinguishable from an
  # operator-backed workload. Nothing needs composing to count controllers.
  # Retried once, because the tree can be MOMENTARILY inconsistent underneath a
  # running walk. A `git rebase` or checkout rewrites tracked files, so a render
  # issued during that window fails on a file that is fine a second later — and
  # since a render failure is instant, the walk burns through workloads at a few
  # seconds each and fails a dozen of them before the window closes. That is
  # exactly how seaweedfs through status-responder failed, all of them rendering
  # perfectly a minute afterwards. A genuine breakage fails both attempts.
  local rendered stage0
  stage0="workloads/${id}/$(jq -r --arg i "$id" '.workloads[]|select(.id==$i)|.stages[0].id' .build/catalog.json).libsonnet"
  if ! rendered="$(kurly::render "$stage0" "" 2>&1)" && ! rendered="$(kurly::render "$stage0" "" 2>&1)"; then
    echo "::error::${id}: its stage did not render, so nothing can be concluded about it — run inside the devShell (nix develop --command …)"
    printf '%s\n' "$rendered" | tail -3
    return 1
  fi
  if ! printf '%s' "$rendered" \
      | jq -e '.items[] | select(.kind=="Deployment" or .kind=="StatefulSet" or .kind=="DaemonSet")' >/dev/null 2>&1; then
    echo "== deep: ${id} renders no standard controller (operator/CR) — fast check only =="
    return 0
  fi
  echo "== DEEP ${id}: deliver through Flux -> JaaS -> stageset =="
  kurly::namespace "$ns" >/dev/null
  kurly::grant_tenant_publish_rbac "$ns"
  # The ServiceAccount the StageSet applies its manifests as (cluster-admin — e2e
  # simplicity, a throwaway cluster).
  kubectl --namespace="$ns" create serviceaccount stageset-deployer --dry-run=client --output=yaml | kubectl apply --filename=-
  kubectl create clusterrolebinding "stageset-deployer-${ns}" --clusterrole=cluster-admin \
    --serviceaccount="${ns}:stageset-deployer" --dry-run=client --output=yaml | kubectl apply --filename=-
  kurly::provision_deps "$id" "$ns"
  # And whatever else the workload needs before its own manifests can run — the
  # same file the fast scenario uses, so the two tiers cannot drift again.
  kurly::prereq "$id" "$ns"
  kurly::publish_images "$id"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec: { interval: 1h, url: oci://ghcr.io/metio/joi-jsonnet-libs-k8s-libsonnet, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec: { sourceRef: { kind: OCIRepository, name: k8s-libsonnet } }
EOF
  kurly::emit_oci_library "$ns" kurly kurly
  kurly::emit_oci_library "$ns" "kurly-${id}" "kurly-${id}"
  kurly::wait_ocirepository "$ns" k8s-libsonnet
  kurly::wait_ocirepository "$ns" kurly
  kurly::wait_ocirepository "$ns" "kurly-${id}"

  # 360s for the first render, 180s once the artifacts are warm.
  local snippetTries=120
  # Stage order matters for a workload whose components depend on each other, and
  # the catalogue's order is alphabetical rather than causal. seaweedfs deploys
  # filer, master, server, volume that way — and the filer talks to the master, so
  # it starts first, finds nothing at -master=, and exits without printing why. The
  # walk then failed a workload whose only problem was the order it was started in.
  #
  # A workload that needs a different order states one in extra.json; everything
  # else keeps the catalogue's, which is right whenever the stages are independent.
  # Stages that actually reached the cluster. A workload whose every stage is a
  # custom resource skips them all, and announcing a delivery for that run said
  # the pipeline had proven something it never touched.
  local deliveredStages=0
  local stageOrder
  stageOrder="$(jq -r --arg id "$id" '(.[$id] // {}).stageOrder // ""' hack/smoke/extra.json 2>/dev/null || true)"
  [ -n "$stageOrder" ] || stageOrder="$(jq -r --arg i "$id" '.workloads[]|select(.id==$i)|.stages[].id' .build/catalog.json)"
  for st in $stageOrder; do
    f="workloads/${id}/${st}.libsonnet"
    snip="${id}-${st}"
    # Discover the stage's primary controller so the StageSet's readyChecks and
    # version source name a real object.
    local composes hostUsers snippetHostUsers
    composes="$(kurly::composes_features "$f")" || {
      echo "::error::deep ${id}: ${st} does not render — a stage that cannot be rendered is a failure, not a stage without a controller"
      kurly::render "$f" 2>&1 | tail -5
      return 1
    }
    hostUsers=""
    snippetHostUsers=""
    if [ "$composes" = yes ]; then
      hostUsers="+ k.hostUsers()"
      snippetHostUsers=" + kurly.hostUsers()"
    fi
    ctrl="$(kurly::render "$f" "$hostUsers" | jq -c '[.items[] | select(.kind=="Deployment" or .kind=="StatefulSet" or .kind=="DaemonSet")][0]')"
    [ "$ctrl" != null ] && [ -n "$ctrl" ] || { echo "== deep: ${st} has no controller, skipping stage =="; continue; }
    deliveredStages=$((deliveredStages + 1))
    kind="$(jq -r '.kind' <<<"$ctrl")"; name="$(jq -r '.metadata.name' <<<"$ctrl")"; apiv="$(jq -r '.apiVersion' <<<"$ctrl")"
    # The same deployment-specific values the fast scenarios compose, from
    # hack/smoke/extra.json. An app that cannot start without knowing its own
    # public URL is given one here rather than the workload carrying a default
    # that would be wrong everywhere it is really deployed — and without it the
    # deep check fails 18 workloads for a value the fast one supplies. cobalt is
    # the plain case: "API_URL env variable is missing, cobalt api can't start".
    ex="$(jq -r --arg k "${id}/${st}" --arg id "$id" '(.[$k] // .[$id] // {}).compose // ""' hack/smoke/extra.json)"
    # The same file's other facet. `compose` is added to an already-built app with
    # `+`; `params` is passed when the stage function is CALLED, which is the only
    # way to reach an argument — metrics-server cannot scrape a kind kubelet
    # without kubeletInsecureTLS, and no amount of composing reaches that.
    params="$(jq -r --arg k "${id}/${st}" --arg id "$id" '(.[$k] // .[$id] // {}).params // ""' hack/smoke/extra.json)"
    # spec.version is OPTIONAL, and only meaningful when the deployed version can
    # be ordered: stageset parses it as semver so a migration ladder knows which
    # way it is moving. kurly stamps app.kubernetes.io/version from the image tag,
    # and a fifth of the catalogue is pinned to something that is not a semver —
    # `latest`, a major-only `10`, a `version-5.7.0`. Declaring the field anyway
    # fails the whole stage with InvalidVersion before anything is applied, which
    # says nothing about whether the workload can be delivered.
    #
    # So it is declared only when the label the StageSet would read actually is a
    # semver. A consumer building a StageSet for a `latest`-tagged workload has to
    # make the same call.
    # A CLUSTER ADD-ON is not a tenant's workload and must not be relocated. Its
    # manifests name the namespace they belong in — metrics-server's RBAC reads a
    # ConfigMap in kube-system through a RoleBinding that lives there — so
    # rewriting every object into kurly-deep-<id> moves the binding out from under
    # the ServiceAccount and the add-on panics on the permission it just lost.
    # The catalogue already derives which stages these are, so ask it rather than
    # keeping a list here.
    clusterScoped="$(jq -r --arg i "$id" --arg s "$st" \
      '.workloads[]|select(.id==$i)|.stages[]|select(.id==$s)|.clusterScoped // false' .build/catalog.json)"
    if [ "$clusterScoped" = true ]; then
      nsRewrite=""
      ctrlNs="$(jq -r '.metadata.namespace // empty' <<<"$ctrl")"; [ -n "$ctrlNs" ] || ctrlNs="$ns"
      echo "== deep: ${id}/${st} is a cluster add-on — applied where it names, not in ${ns} =="
      # And the namespaces it names have to EXIST. A tenant's workload lands in a
      # namespace the walk created; an add-on brings its own, and stageset applies
      # rather than creates it — metrics-server got away with kube-system because
      # that is always there, opencost failed on "namespaces \"opencost\" not
      # found". Create every namespace the render mentions, not just the
      # controller's, since the RBAC and ServiceAccount may name others.
      local addonNs
      for addonNs in $(kurly::render "$f" "$hostUsers" 2>/dev/null \
        | jq -r '[.items[].metadata.namespace // empty] | unique | .[]'); do
        kurly::namespace "$addonNs" >/dev/null
      done
    else
      nsRewrite=" { items: [ item { metadata+: { namespace: '${ns}' } } for item in rendered.items ] }"
      ctrlNs="$ns"
    fi
    version="$(jq -r '.metadata.labels["app.kubernetes.io/version"] // ""' <<<"$ctrl")"
    versionBlock=""
    # ANCHORED at both ends, and this matters: an unanchored prefix test accepts
    # everything that merely STARTS like a semver, and a four-component version is
    # the common shape that does — 3.3.1.0, v2.3.0.4_stable_2026-07-09-ls301. Those
    # are not semver, stageset rejects them, and the stage fails InvalidVersion
    # before anything is applied. Seven of the catalogue's 320 tags are that shape.
    # A leading v is fine (stageset strips it); a pre-release or build suffix is
    # part of the grammar and allowed.
    if [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
      versionBlock=$'\n  version:\n    fromObject: { stage: '"${st}"', apiVersion: '"${apiv}"', kind: '"${kind}"', name: '"${name}"' }'
    else
      echo "== deep: ${id}/${st} is pinned to '${version:-<none>}', which is not a semver — the StageSet declares no spec.version =="
    fi
    kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ${snip}, namespace: ${ns} }
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  # Without these the snippet has nothing to import FROM: JaaS mounts the
  # libraries a snippet names, and an absolute github.com/... import resolves
  # through their vendor trees. Omitting them fails every render with
  # EvaluationFailed, identically for every workload — which reads like a broken
  # library rather than a snippet that asked for none.
  #
  # No importPath: both images key their files by full vendor path already, so
  # the alias (defaulting to the library's name) only matters for bare-name
  # imports. Same shape as the hand-written deep scenarios.
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
    - { kind: JsonnetLibrary, name: kurly-${id} }
    - { kind: JsonnetLibrary, name: k8s-libsonnet }
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      // The extra fragments in hack/smoke/extra.json are written against \`k\`,
      // the alias the fast scenarios use; bind it so they compose verbatim here.
      local k = kurly;
      local stage = import 'github.com/metio/kurly/${f}';
      local rendered = kurly.list(stage(${params})${snippetHostUsers}${ex});
      rendered${nsRewrite}
EOF
    # The FIRST snippet of a run pays for a cold cluster: JaaS pulls three OCI
    # artifacts (k8s-libsonnet, the library, the workload) before it can render
    # at all, while later snippets reuse them. One timeout for both makes a slow
    # first render look exactly like a broken one — and only ever on whichever
    # workload happens to sort first, which is how a day gets lost to a flake.
    kurly::wait_ready "$ns" jsonnetsnippet "$snip" "$snippetTries" \
      || { kurly::diagnose_pipeline "$ns"; echo "::error::deep ${id}: jsonnetsnippet/${snip} never rendered"; return 1; }
    snippetTries=60
    kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ${snip}, namespace: ${ns} }
spec:
  interval: 1m
  # No timeout here on purpose: stageset's default is 15m since
  # stageset-controller 2026.7.31092513, which is more than this walk would have
  # chosen and more than the workloads that migrate before serving need. The
  # ladder is readyChecks.timeout -> stages[].timeout -> spec.timeout -> 15m.
  serviceAccountName: stageset-deployer${versionBlock}
  stages:
    - name: ${st}
      sourceRef: { name: ${snip} }
      readyChecks:
        checks:
          - { apiVersion: ${apiv}, kind: ${kind}, name: ${name}, namespace: ${ctrlNs} }
EOF
    # The StageSet goes Ready only once its readyChecks see the controller healthy,
    # so this budget is the APP's startup budget, not the controller's. It has to
    # be at least as generous as the fast tier's (KURLY_ROLLOUT_TIMEOUT, 300s) —
    # the deep path does strictly more before the app even starts, since it pulls
    # three OCI artifacts, renders, and applies. At 90 polls it was 270s, tighter
    # than the fast tier, and workloads that run migrations before serving
    # (authentik, and it will not be alone) were failing at 4m32s while Running
    # with zero restarts: healthy, just not finished starting.
    # This number is the WALK'S OWN ANSWER to "how long am I willing to wait for an
    # application to start". It used to be a safety margin over stageset's 15m
    # timeout, so the run would read stageset's verdict rather than pre-empt it —
    # but a stage whose verify runs out of time no longer produces a verdict to
    # outlast. It reports StageProgressing and HOLDS: the objects stay applied, the
    # stage re-verifies each reconcile, and it goes Ready when the workload does.
    # So at 3s a poll, 340 polls means the walk gives up at 17 minutes on a
    # StageSet that might have converged at 18, and nothing else bounds it.
    #
    # A genuinely broken workload still fails in seconds — the verify aborts as
    # soon as an object reaches a terminal state (unpullable image, crash-looping
    # past its threshold). This budget only separates "slow" from "too slow".
    kurly::wait_ready "$ns" stageset "$snip" "${KURLY_STAGESET_POLLS:-340}" \
      || {
        kurly::diagnose "$ns"
        # A cluster add-on applies where it NAMES, not in the walk's namespace, so
        # the pods that failed are somewhere else entirely. Diagnosing only $ns
        # printed sources and events for a namespace containing none of the
        # workload — opencost failed twice with "Deployment/opencost/opencost
        # status: Failed" and no pod, log or event to say why, and cleanup then
        # destroyed the evidence.
        if [ "$ctrlNs" != "$ns" ]; then kurly::diagnose "$ctrlNs"; fi
        kurly::diagnose_pipeline "$ns"
        # WHICH of the two happened, because they want opposite follow-ups and
        # both used to print as "never became Ready": StageProgressing means the
        # app was still starting and the budget was too small — the workload is
        # fine and the harness was impatient — while StageFailed means the stage
        # broke and the workload wants diagnosing.
        kubectl --namespace="$ns" get stageset -o custom-columns=\
'NAME:.metadata.name,REASON:.status.conditions[?(@.type=="Ready")].reason,MSG:.status.conditions[?(@.type=="Ready")].message' 2>&1 || true
        echo "::error::deep ${id}: stageset/${snip} never became Ready"
        return 1
      }
    kubectl --namespace="$ctrlNs" rollout status "${kind,,}/${name}" --timeout=300s \
      || {
        kurly::diagnose "$ns"
        if [ "$ctrlNs" != "$ns" ]; then kurly::diagnose "$ctrlNs"; fi
        kurly::diagnose_pipeline "$ns"
        echo "::error::deep ${id}: ${kind}/${name} never rolled out via stageset"
        return 1
      }
  done
  if [ "$deliveredStages" -eq 0 ]; then
    echo "== deep: ${id} has no stage with a controller — nothing was delivered =="
    return 0
  fi
  echo "ok: ${id} delivered end-to-end through Flux -> JaaS -> stageset"
}

# Blocks until a resource's Ready condition is true (or times out loudly). The
# namespace is explicit: every object this waits on lives in the scenario's own
# namespace, never the context's, so a lookup without it reports a rendered
# snippet as one that never appeared.
#   kurly::wait_ready <namespace> <resource> <name> [tries]
kurly::wait_ready() {
  local ns="$1" res="$2" name="$3" tries="${4:-60}" i
  for i in $(seq 1 "$tries"); do
    [ "$(kubectl --namespace="$ns" get "$res" "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)" = True ] \
      && return 0
    sleep 3
  done
  echo "::error::${res}/${name} never became Ready"; return 1
}

# Dumps everything useful about a namespace on failure, grouped in the log.
kurly::diagnose() {
  local ns="$1"
  echo "::group::diagnostics ($ns)"
  kubectl --namespace="$ns" get all,pvc,endpoints 2>/dev/null || true
  kubectl --namespace="$ns" get pods --show-labels 2>/dev/null || true
  kubectl --namespace="$ns" describe pods 2>/dev/null | tail -120 || true
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=kurly --all-containers=true --tail=100 2>/dev/null || true
  # A container in CrashLoopBackOff has no live logs — the output that explains why
  # it died belongs to the previous instance.
  echo "--- previous container logs ---"
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=kurly --all-containers=true --tail=100 --previous 2>/dev/null || true
  kubectl --namespace="$ns" get events --sort-by=.lastTimestamp 2>/dev/null | tail -40 || true
  echo "::endgroup::"
}

# Dumps the Flux + JaaS + stageset pipeline objects on failure. The Ready
# condition message of the JsonnetSnippet and the StageSet is where import,
# render, and apply errors surface, so print each one's full status.
kurly::diagnose_pipeline() {
  local ns="$1"
  echo "::group::pipeline diagnostics ($ns)"
  # The controllers' own pods and logs FIRST — bulky, and where a hang that never
  # writes a condition (an OOMKill, a crash, a stuck fetch) shows up. Ordered
  # ahead of the conditions on purpose: a long CI log is read from its tail, and
  # the tail should hold the answer rather than a controller's startup banner.
  echo "--- JaaS operator (pods + logs) ---"
  kubectl --namespace=jaas-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=jaas-system logs --selector=app.kubernetes.io/instance=jaas \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
  echo "--- stageset-controller (pods + logs) ---"
  kubectl --namespace=stageset-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=stageset-system logs --selector=app.kubernetes.io/instance=stageset \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
  echo "--- sources and objects in ${ns} ---"
  kubectl --namespace="$ns" get gitrepository,ocirepository,jsonnetlibrary,jsonnetsnippet,externalartifact,stageset,stageinventory -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get deployments,statefulsets,daemonsets,services,pods -o wide 2>/dev/null || true
  echo "--- StageInventory (what stageset applied) ---"
  kubectl --namespace="$ns" get stageinventory -o yaml 2>/dev/null | grep -iE "kind:|name:|namespace:|apiVersion:" | head -40 || true
  # LAST, and asked by namespace rather than by a guessed name: the condition
  # MESSAGE. A reason names the kind of failure; only the message says which
  # import did not resolve or which assert fired.
  echo "--- CONDITIONS (the answer, kept last so a truncated log still carries it) ---"
  kubectl --namespace="$ns" get jsonnetsnippet -o jsonpath=\
'{range .items[*]}snippet/{.metadata.name}{"\n"}{range .status.conditions[*]}  {.type}={.status} reason={.reason}{"\n"}  message={.message}{"\n"}{end}{end}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" get stageset -o jsonpath=\
'{range .items[*]}stageset/{.metadata.name}{"\n"}{range .status.conditions[*]}  {.type}={.status} reason={.reason}{"\n"}  message={.message}{"\n"}{end}{end}' 2>/dev/null || true
  echo
  # Every pod that is not Running, with why — an ImagePullBackOff or a crash loop
  # is the other half of "the rollout never completed".
  echo "--- pods not Running ---"
  kubectl --namespace="$ns" get pods -o json 2>/dev/null \
    | jq -r '.items[] | select(.status.phase != "Running") | "\(.metadata.name) \(.status.phase) \([.status.containerStatuses[]?.state | to_entries[] | "\(.key): \(.value.reason // "")\(if .value.message then " — " + .value.message else "" end)"] | join("; "))"' 2>/dev/null || true
  echo "::endgroup::"
}

# Installs the FULL Flux suite (always the latest release) and opens the
# source-controller artifact port cluster-wide. JaaS needs the ExternalArtifact
# kind, which ships in source-controller v1.7.0+ (Flux v2.7.0+).
kurly::install_flux() {
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r .tag_name 2>/dev/null || true)"
  [ -n "$ver" ] && [ "$ver" != "null" ] || ver="v2.7.0"
  echo "== install Flux ${ver} =="
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "https://github.com/fluxcd/flux2/releases/download/${ver}/install.yaml"
  kubectl -n flux-system rollout status deploy/source-controller --timeout=300s

  # Flux's default `allow-egress` NetworkPolicy admits ingress to source-controller
  # only from pods inside flux-system, and `allow-scraping` opens only the metrics
  # port (8080). The artifact HTTP server listens on 9090, so an operator running
  # outside flux-system can't fetch artifacts once the CNI enforces NetworkPolicies
  # (recent kindnet does; older kindnet treated them as no-ops). Open the artifact
  # port cluster-wide so the operator — and any tenant namespace — can reach it.
  kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-artifact-fetch
  namespace: flux-system
spec:
  podSelector:
    matchLabels:
      app: source-controller
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - port: 9090
          protocol: TCP
EOF
}

# Installs JaaS from its released chart (latest). The webhook is off to avoid a
# cert-manager dependency; the bundled shared libraries are off because kind lacks
# the ImageVolume feature gate they mount through.
kurly::install_jaas() {
  echo "== install JaaS (helm) =="
  # The chart's default 64Mi is far too small to render k8s-libsonnet (go-jsonnet
  # peaks at hundreds of MB), so the operator OOMKills on the first reconcile —
  # give it room.
  helm upgrade --install jaas oci://ghcr.io/metio/helm-charts/jaas \
    --namespace jaas-system --create-namespace \
    --set operator.enabled=true \
    --set operator.defaultServiceAccount=default \
    --set operator.webhook.enabled=false \
    --set libraries.grafonnet.enabled=false \
    --set libraries.docsonnet.enabled=false \
    --set libraries.xtd.enabled=false \
    --set resources.memory=2Gi \
    --wait --timeout 5m
  kubectl -n jaas-system rollout status deploy \
    --selector app.kubernetes.io/name=jaas --timeout=300s || true
}

# Installs the stageset-controller from its released chart (latest).
kurly::install_stageset() {
  echo "== install stageset-controller (helm) =="
  helm upgrade --install stageset oci://ghcr.io/metio/helm-charts/stageset-controller \
    --namespace stageset-system --create-namespace \
    --wait --timeout 5m
}

# grant_tenant_publish_rbac <ns> [sa] — grant the tenant ServiceAccount (default
# "default") the RBAC the operator needs while impersonating it to publish: get /
# list / watch / create / update / patch / delete the snippet's ExternalArtifact
# and write its status. The operator acts AS the tenant SA (no `impersonate` verb
# on its own SA), so without this every reconcile fails RBACDenied at the publish
# step and the snippet never goes Ready.
kurly::grant_tenant_publish_rbac() {
  local ns=$1 sa=${2:-default}
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
rules:
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["externalartifacts", "externalartifacts/status"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # The operator impersonates the tenant SA to READ the JsonnetLibrary resources
  # the snippet references, so grant read access to them too. (Inline-only
  # snippets don't need this; ours references the kurly + k8s-libsonnet libs.)
  - apiGroups: ["jaas.metio.wtf"]
    resources: ["jsonnetlibraries"]
    verbs: ["get", "list", "watch"]
  # A source-backed JsonnetLibrary (ours: k8s-libsonnet from an OCIRepository)
  # makes the operator read that source CR for its artifact URL, so grant read on
  # the Flux source kinds (git/bucket too, so the helper generalizes).
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["ocirepositories", "gitrepositories", "buckets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
subjects:
  - { kind: ServiceAccount, name: ${sa}, namespace: ${ns} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: jaas-tenant-publish }
EOF
}

# The in-cluster registry that serves the branch-built images to Flux. The
# stageset scenarios consume kurly through the SAME path a real deployment does —
# an OCIRepository — instead of an inline JsonnetLibrary, so the image packaging
# (the Containerfiles, the single layer, the vendor-tree layout) is exercised on
# every run, not just at release. Building from the checkout keeps the "tests the
# exact branch" property the inline library had.
#
# One registry, reached two ways: the host pushes over a NodePort the e2e
# workflow maps to localhost:5001 (registry:true), and source-controller pulls
# over the ClusterIP by DNS. Plain HTTP, so the host push relies on Docker
# trusting localhost and the OCIRepository sets `insecure: true`.
KURLY_REGISTRY_PUSH="localhost:5001"
KURLY_REGISTRY_PULL="registry.registry.svc.cluster.local:5000"
KURLY_IMAGE_TAG="e2e"

# Deploys registry:2 in its own namespace with a fixed NodePort, and waits for it
# to serve. The NodePort (30500) is the one the workflow's kind config maps to the
# host, so a scenario that calls this MUST run under a `registry: true` e2e job.
kurly::install_registry() {
  echo "== install in-cluster registry =="
  kubectl apply --filename=- <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: registry }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: registry, namespace: registry }
spec:
  replicas: 1
  selector: { matchLabels: { app: registry } }
  template:
    metadata: { labels: { app: registry } }
    spec:
      containers:
        - name: registry
          image: docker.io/library/registry:2
          ports:
            - { containerPort: 5000 }
---
apiVersion: v1
kind: Service
metadata: { name: registry, namespace: registry }
spec:
  type: NodePort
  selector: { app: registry }
  ports:
    - { port: 5000, targetPort: 5000, nodePort: 30500, protocol: TCP }
EOF
  kubectl -n registry rollout status deploy/registry --timeout=180s
}

# Builds the branch's library and workload images and pushes them to the registry
# through the host port-map. Usage: kurly::publish_images <workload>...
# The library is always published (every stage imports it); each named workload's
# source image is published too. Push is retried, since the NodePort route can lag
# the pod becoming Ready.
kurly::publish_images() {
  local push
  # The registry speaks plain HTTP. Docker treats a localhost registry as insecure
  # and pushes anyway; Podman pings it over HTTPS and fails unless told otherwise,
  # while Docker does not know the flag at all. The client is identified by whether
  # it offers the flag — Podman invoked through a `docker` symlink reports itself as
  # "docker version 5.x", so the version string cannot tell them apart.
  local push_flags=()
  if docker push --help 2>/dev/null | grep -q -- --tls-verify; then push_flags+=(--tls-verify=false); fi
  _push() {
    local ref="$1" i out
    for i in $(seq 1 12); do
      out="$(docker push --quiet "${push_flags[@]}" "$ref" 2>&1)" && return 0
      echo "push $ref failed (attempt $i) — retrying"
      sleep 5
    done
    # The last attempt's output, not just the count: a push that fails twelve times
    # for one reason otherwise reports only that it kept failing.
    echo "push $ref never succeeded: $out" >&2
    return 1
  }
  # The library is identical for the whole walk, so it is built and pushed once.
  # Rebuilding it per workload emitted twenty-five lines of cached build output
  # three hundred times, which is how a failure ends up buried a hundred lines
  # above the end of a log nobody can read to the middle of.
  if [ -z "${KURLY_LIBRARY_PUBLISHED:-}" ]; then
    echo "== build and push the kurly library image =="
    push="${KURLY_REGISTRY_PUSH}/kurly:${KURLY_IMAGE_TAG}"
    docker build --quiet --file Containerfile --tag "$push" . >/dev/null
    _push "$push"
    export KURLY_LIBRARY_PUBLISHED=1
  fi
  local wl
  for wl in "$@"; do
    echo "== build and push the ${wl} workload image =="
    push="${KURLY_REGISTRY_PUSH}/kurly-${wl}:${KURLY_IMAGE_TAG}"
    docker build --quiet --file workload.Containerfile --build-arg "WORKLOAD=${wl}" --tag "$push" . >/dev/null
    _push "$push"
  done
}

# Emits an OCIRepository (pulling from the in-cluster registry, insecure HTTP) and
# the JsonnetLibrary that sources it. Usage:
#   kurly::emit_oci_library <ns> <library-name> <image-repo>
# e.g. `kurly::emit_oci_library cache kurly kurly` and
#      `kurly::emit_oci_library cache kurly-valkey kurly-valkey`.
kurly::emit_oci_library() {
  local ns="$1" name="$2" repo="$3"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: ${name}, namespace: ${ns} }
spec:
  interval: 1h
  insecure: true
  url: oci://${KURLY_REGISTRY_PULL}/${repo}
  ref: { tag: ${KURLY_IMAGE_TAG} }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: ${name}, namespace: ${ns} }
spec:
  sourceRef: { kind: OCIRepository, name: ${name} }
EOF
}

# Blocks until an OCIRepository advertises a fetched artifact (or fails loudly).
kurly::wait_ocirepository() {
  local ns="$1" name="$2" i
  for i in $(seq 1 60); do
    [ -n "$(kubectl --namespace="$ns" get ocirepository/"$name" -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
      && { echo "ocirepository/${name} has an artifact"; return 0; }
    sleep 3
  done
  echo "ocirepository/${name} never advertised an artifact" >&2
  return 1
}
