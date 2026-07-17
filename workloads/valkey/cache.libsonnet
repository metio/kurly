// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// valkey (in-memory cache, zero-downtime version hand-off) — a Valkey cache that
// upgrades its version without downtime or data loss, on the OFFICIAL upstream
// image and with no orchestrator: the hand-off lives entirely in the pod's own
// manifests, so a plain `kubectl apply`, a Helm upgrade, or a stageset roll all
// trigger it identically.
//
// The mechanism (a manifests-only transcription of the same replication hand-off
// a custom image would bake in):
//   - a headless Service lets pods find each other by DNS;
//   - a RollingUpdate with maxSurge=1 starts the new-version pod BESIDE the old;
//   - an initContainer discovers the running peer and writes a config that
//     REPLICAOFs it, so the new pod boots as a secondary and syncs the dataset;
//   - readiness is `master_link_status:up`, so the new pod is Ready only once in
//     sync — which is when Kubernetes removes the old one;
//   - the old pod's preStop runs Valkey's own atomic `failover`, promoting the
//     new pod before it terminates. No lost writes, no split brain.
//
// Persistence is off (a cache): the dataset moves by replication on every
// rollover, not through a volume. Clients connect at valkey-headless:6379.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline rewrites 'dev' to the calver.
local version = 'dev';

function(
  name='valkey',
  image='docker.io/valkey/valkey:9.0.3',
  maxMemory='256mb',
  // The sidecar that labels the primary pod — a maintained Alpine image carrying
  // kubectl plus busybox `nc` and `sh` (the role probe needs neither bash nor a
  // Valkey client); overridable. Only this workload's plumbing runs it — the
  // Valkey data container stays the stock image.
  kubectlImage='docker.io/alpine/k8s:1.36.2',
)
  local headless = name + '-headless';
  local roleLabel = 'kurly.dev/valkey-role';

  // Discover the peer that is actually the primary and write a config that
  // replicates it. The whole server config is generated here so the stock image
  // needs no baked-in scripts; the probe uses the image's own valkey-cli.
  //
  // Every peer is probed rather than trusting the first name the headless
  // Service resolves. The Service lists a pod until its endpoint is withdrawn,
  // which lags the pod's death by seconds — so during a roll the set can still
  // name the previous generation's pod, and a replica pointed at a terminating
  // peer never syncs and never becomes ready. An unreachable peer fails the
  // probe and is skipped; a replica reports role:slave and is skipped.
  //
  // The fallback matters as much as the preference: with peers alive but none
  // yet a primary (the instant between a hand-off and the new primary taking
  // the role), replicating the first reachable peer chains behind whoever wins
  // and converges. Starting as a primary there would strand a second writer.
  local initScript = |||
    set -eu
    my_ip="$(hostname -i | awk '{print $1}')"
    primary=''
    reachable=''
    for ip in $(getent hosts %(headless)s | awk '{print $1}' | grep -v "^${my_ip}$" || true); do
      info="$(timeout 2 valkey-cli -h "$ip" info replication 2>/dev/null || true)"
      [ -n "$info" ] || continue
      [ -n "$reachable" ] || reachable="$ip"
      if printf '%%s' "$info" | grep -q 'role:master'; then primary="$ip"; break; fi
    done
    [ -n "$primary" ] || primary="$reachable"
    {
      echo 'dir /gen'
      echo 'save ""'
      echo 'appendonly no'
      echo 'maxmemory %(maxMemory)s'
      echo 'maxmemory-policy allkeys-lru'
      if [ -n "$primary" ]; then echo "replicaof ${primary} 6379"; else echo '# no peer: starting as primary'; fi
    } > /gen/valkey.conf
    cat /gen/valkey.conf
  ||| % { headless: headless, maxMemory: maxMemory };

  // If this pod is the primary with a connected replica, hand off with Valkey's
  // own atomic failover before terminating; a secondary (or a lone primary)
  // exits at once.
  local preStopScript = |||
    valkey-cli role | grep -q slave && exit 0
    valkey-cli info replication | grep -q 'connected_slaves:0' && exit 0
    valkey-cli failover
    i=0
    while [ "$i" -lt 60 ]; do
      valkey-cli role | grep -q slave && exit 0
      i=$((i + 1))
      sleep 1
    done
  |||;

  // The role labeler: probe the local Valkey's replication role with busybox
  // `nc` (no bash, no Valkey client) and keep this pod's `roleLabel` in sync —
  // set to `primary` on the master, removed on a replica (a merge patch with a
  // null value deletes the key). `kubectl patch` reads the pod before writing, so
  // the sidecar's Role needs `get` and `patch` on pods (nothing more). The primary
  // Service selects that label, so clients always reach the current master, even
  // across the hand-off — the label moves to the promoted pod within a poll, so
  // the Service never routes to a replica. It polls roughly once a second (the
  // `nc` hold paces the loop) and writes only when the role changes, so steady
  // state makes no API calls. HOME is a writable emptyDir so kubectl can cache
  // under a read-only root filesystem.
  local labelerScript = |||
    set -u
    export HOME=/home/labeler
    escaped='%(roleLabel)s'
    last=''
    while true; do
      if { printf 'INFO replication\r\n'; sleep 1; } | timeout 2 nc 127.0.0.1 6379 2>/dev/null | grep -q 'role:master'; then
        value='"primary"'
      else
        value=null
      fi
      if [ "$value" != "$last" ]; then
        if kubectl patch pod "$POD_NAME" --type=merge \
          -p "{\"metadata\":{\"labels\":{\"$escaped\":$value}}}" >/dev/null 2>&1; then
          last="$value"
        else
          echo "labeler: failed to patch ${escaped} on ${POD_NAME}" >&2
        fi
      fi
    done
  ||| % { roleLabel: roleLabel };

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.runAs(999)
  // A writable scratch for the generated config (and Valkey's working dir); the
  // root filesystem stays read-only.
  + kurly.scratch('/gen')
  + kurly.command(['valkey-server', '/gen/valkey.conf'])
  + kurly.headlessService(port=6379, publishNotReady=true)
  + kurly.rollingUpdate(maxSurge=1, maxUnavailable=0)
  + kurly.terminationGracePeriod(120)
  // No securityContext here: the init container inherits the workload's composed
  // posture, so kurly.runAs() and the security profiles reach it. Pinning a uid
  // here would leave it behind on a cluster where uids are assigned rather than
  // chosen.
  + kurly.initContainer({
    name: 'discover-primary',
    image: image,
    command: ['sh', '-c', initScript],
    volumeMounts: [{ name: 'gen', mountPath: '/gen' }],
  })
  + kurly.lifecycle(preStop={ exec: { command: ['sh', '-c', preStopScript] } })
  + kurly.readinessProbe({ exec: { command: ['sh', '-c', "valkey-cli info replication | grep -qE 'role:master|master_link_status:up'"] } })
  // The labeler is a Kubernetes API client: it needs a Role to read and label its
  // pod AND network egress to the apiserver. apiServerClient declares both as
  // cross-cutting requirements, so a consumer's own rbac()/networkPolicy() cannot
  // clobber this grant or firewall off the labeler. `get` + `patch` on pods is the
  // whole grant (no `list`, `watch`, `create`, or `delete`) — a namespaced Role.
  // It cannot be narrowed to this one pod: RBAC `resourceNames` cannot match the
  // controller's generated pod names, so the grant is namespace-wide on pods.
  + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['get', 'patch'] }])
  // The labeler runs beside Valkey as a sidecar, so it inherits the composed
  // security posture instead of restating one — a uid written here would ignore
  // kurly.runAs() and strand the pod on a cluster that assigns uids.
  + kurly.sidecar({
    name: 'role-labeler',
    image: kubectlImage,
    command: ['sh', '-c', labelerScript],
    env: [{ name: 'POD_NAME', valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } }],
    resources: { requests: { cpu: '10m', memory: '32Mi' }, limits: { memory: '32Mi' } },
    // A writable HOME so kubectl can cache under the read-only root filesystem;
    // the pod's fsGroup owns the emptyDir.
    volumeMounts: [{ name: 'labeler-home', mountPath: '/home/labeler' }],
  })
  // The primary Service is this workload's own plumbing, added with the raw `+`
  // escape hatch rather than a library feature.
  + {
    local this = self,
    deployment+: {
      spec+: { template+: { spec+: {
        volumes+: [{ name: 'labeler-home', emptyDir: {} }],
      } } },
    },
    // Clients connect here; it resolves only to the pod the labeler marks primary.
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: name, labels: { 'app.kubernetes.io/name': name, 'app.kubernetes.io/managed-by': 'kurly', 'app.kubernetes.io/version': version } },
      // The IP families come from the same fragment every other Service uses:
      // written by hand they would hold the cluster's default while the headless
      // Service beside them followed the consumer, and clients would reach the
      // primary over a family the rest of the workload does not speak.
      spec: {
        selector: { 'app.kubernetes.io/name': name, [roleLabel]: 'primary' },
        ports: [{ name: 'redis', port: 6379, targetPort: 6379 }],
      } + this.ipFamilySpec,
    },
  }
