// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// features: the composable capabilities of a workload, each a function
// returning a `{ config+:: … }` mixin you add with `+`. A feature only ever
// contributes to config — never to a manifest directly — so the kind's
// computed manifests late-bind against the merged config regardless of the
// order features are composed:
//
//   kurly.http('tik', image)
//   + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
//   + kurly.store('/var/lib/tik', '1Gi')
//   + kurly.config({ 'pipelines.edn': edn })
//   + kurly.runAs(12345)
//   + kurly.recreate()
// Named resource presets — a memory request equal to its limit (a Guaranteed
// memory footprint) and a CPU request with no limit (CPU throttling is usually
// worse than letting a pod burst). resourcePreset picks one; resources sets an
// explicit pair.
local resourcePresets = {
  nano: { requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '64Mi' } },
  micro: { requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '128Mi' } },
  small: { requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '256Mi' } },
  medium: { requests: { cpu: '500m', memory: '512Mi' }, limits: { memory: '512Mi' } },
  large: { requests: { cpu: '1', memory: '1Gi' }, limits: { memory: '1Gi' } },
};

{
  // Container basics.
  image(image):: { config+:: { image: image } },
  port(port):: { config+:: { port: port } },
  replicas(replicas):: { config+:: { replicas: replicas } },
  // args appends arguments to the image's own entrypoint (a subcommand
  // selecting the workload); command overrides the entrypoint itself.
  args(args):: { config+:: { args: args } },
  command(command):: { config+:: { command: command } },
  env(env):: { config+:: { env+: env } },
  // The workload version, stamped as app.kubernetes.io/version on every object.
  version(version):: { config+:: { version: version } },
  labels(labels):: { config+:: { labels+: labels } },
  annotations(annotations):: { config+:: { annotations+: annotations } },
  // podLabels/podAnnotations land on the pod template ONLY (never the workload
  // metadata, never the immutable selector) — for network-policy selectors, log
  // collection, and sidecar-injection annotations that are meaningless on the
  // controller object.
  podLabels(podLabels):: { config+:: { podLabels+: podLabels } },
  podAnnotations(podAnnotations):: { config+:: { podAnnotations+: podAnnotations } },
  // imagePullSecrets names existing Secrets the kubelet uses to pull the image;
  // priorityClassName sets the pod's scheduling priority.
  imagePullSecrets(names):: { config+:: { imagePullSecrets+: names } },
  priorityClassName(priorityClassName):: { config+:: { priorityClassName: priorityClassName } },
  resources(requests=null, limits=null):: {
    config+:: {
      resources+:
        (if requests == null then {} else { requests: requests })
        + (if limits == null then {} else { limits: limits }),
    },
  },
  // resourcePreset picks a named size (nano/micro/small/medium/large) instead of
  // spelling out requests and limits; it replaces the resources wholesale, so
  // compose it before any single-knob resources() tweak.
  resourcePreset(preset):: { config+:: { resources: resourcePresets[preset] } },
  serviceAccount(serviceAccountName):: { config+:: { serviceAccountName: serviceAccountName } },
  // HTTP readiness+liveness probes on the named `http` port.
  probes(path='/healthz'):: { config+:: { probePath: path } },
  // Explicit probe specs (exec, tcpSocket, httpGet, …) that override the default
  // http probes — passed through verbatim.
  readinessProbe(probe):: { config+:: { readinessProbe: probe } },
  livenessProbe(probe):: { config+:: { livenessProbe: probe } },
  // Container lifecycle handlers (postStart / preStop), passed through verbatim.
  lifecycle(preStop=null, postStart=null):: {
    config+:: { lifecycle+: std.prune({ preStop: preStop, postStart: postStart }) },
  },
  // An init container that runs to completion before the main one starts —
  // the full container spec, passed through. Composes more than once.
  initContainer(container):: { config+:: { initContainers+: [container] } },
  // An extra container beside the workload's own, sharing the pod. It inherits
  // the composed security posture unless it carries its own securityContext —
  // so a sidecar does not have to restate a uid, and does not silently keep one
  // when the consumer changes it.
  sidecar(container):: { config+:: { sidecars+: [container] } },
  // How long the pod gets to shut down gracefully (a preStop hook's window).
  terminationGracePeriod(seconds):: { config+:: { terminationGracePeriodSeconds: seconds } },
  // A headless Service (clusterIP: None) selecting the pods, for DNS peer
  // discovery. publishNotReady lists pods before they are Ready.
  headlessService(port=null, publishNotReady=false):: {
    config+:: { headlessService: { port: port, publishNotReadyAddresses: publishNotReady } },
  },
  // RollingUpdate tuning so a new pod can surge alongside the old during an
  // update — the overlap a replication hand-off needs.
  rollingUpdate(maxSurge=null, maxUnavailable=null):: {
    config+:: { strategy: 'RollingUpdate', rollingUpdate: std.prune({ maxSurge: maxSurge, maxUnavailable: maxUnavailable }) },
  },

  // CronJob tuning (only kurly.cron reads these).
  schedule(schedule):: { config+:: { schedule: schedule } },
  concurrencyPolicy(concurrencyPolicy):: { config+:: { concurrencyPolicy: concurrencyPolicy } },

  // Storage and mounts. store adds the workload's own PVC and mounts it; config
  // renders a ConfigMap from a filename->content map and mounts it read-only;
  // secretMount mounts an EXISTING Secret (kurly never mints key material);
  // scratch adds a writable emptyDir — the escape valve a read-only root
  // filesystem needs for /tmp and the like.
  store(mountPath, size, accessModes=['ReadWriteOnce'], storageClass=null, selector={}, annotations={}):: {
    config+:: {
      store: {
        mountPath: mountPath,
        size: size,
        accessModes: accessModes,
        storageClass: storageClass,
        selector: selector,
        annotations: annotations,
      },
    },
  },
  config(files, mountPath='/etc/config'):: {
    config+:: { configFiles: { mountPath: mountPath, files: files } },
  },
  secretMount(secretName, mountPath, readOnly=true, optional=false, defaultMode=null):: {
    config+:: {
      secretMounts+: [{
        secretName: secretName,
        mountPath: mountPath,
        readOnly: readOnly,
        optional: optional,
        defaultMode: defaultMode,
      }],
    },
  },
  scratch(mountPath, sizeLimit=null):: {
    config+:: { scratch+: [{ mountPath: mountPath, sizeLimit: sizeLimit }] },
  },

  // A pinned run-as user/group (and matching fsGroup) for images that do not
  // declare a non-root USER themselves, or that must own a mounted volume's
  // files. gid defaults to uid; fsGroup defaults to gid.
  runAs(uid, gid=null, fsGroup=null):: {
    config+:: {
      runAsUser: uid,
      runAsGroup: if gid == null then uid else gid,
      fsGroup: if fsGroup == null then (if gid == null then uid else gid) else fsGroup,
    },
  },

  // Deployment update strategy. recreate is the single-writer case: a
  // ReadWriteOnce store cannot be mounted by a second pod while the old one
  // holds it, so a rolling update would deadlock.
  strategy(strategy):: { config+:: { strategy: strategy } },
  recreate():: { config+:: { strategy: 'Recreate' } },

  // Pod scheduling and placement. Each is merged onto the pod template verbatim
  // — kurly does not model the Kubernetes schema (it would drift), the same
  // pass-through stance as migration actions. nodeSelector and tolerations
  // accumulate; topologySpread appends constraints; affinity merges the object.
  nodeSelector(nodeSelector):: { config+:: { nodeSelector+: nodeSelector } },
  tolerations(tolerations):: { config+:: { tolerations+: tolerations } },
  topologySpread(constraints):: { config+:: { topologySpread+: constraints } },
  affinity(affinity):: { config+:: { affinity+: affinity } },

  // Owned manifests — each adds a resource beyond the pod controller, targeting
  // the workload's own pods by its stable selector. pdb caps voluntary
  // disruption; hpa autoscales the Deployment on CPU/memory; networkPolicy
  // firewalls the pods (rules passed through verbatim); serviceMonitor wires
  // Prometheus scraping; rbac mints a ServiceAccount + Role + RoleBinding and
  // runs the pod under it.
  pdb(minAvailable=null, maxUnavailable=null):: {
    config+:: { pdb: { minAvailable: minAvailable, maxUnavailable: maxUnavailable } },
  },
  hpa(minReplicas, maxReplicas, targetCPU=null, targetMemory=null):: {
    config+:: { hpa: { minReplicas: minReplicas, maxReplicas: maxReplicas, targetCPU: targetCPU, targetMemory: targetMemory } },
  },
  networkPolicy(ingress=[], egress=[], policyTypes=null):: {
    config+:: { networkPolicy: { ingress: ingress, egress: egress, policyTypes: policyTypes } },
  },
  serviceMonitor(port='http', path='/metrics', interval=null):: {
    config+:: { serviceMonitor: { port: port, path: path, interval: interval } },
  },
  rbac(rules):: { config+:: { rbac: { rules: rules } } },
  // Declares that a pod (or one of its sidecars) is a Kubernetes API client: it
  // needs the given Role `rules` AND network egress to the apiserver. Both travel
  // as cross-cutting requirements, so a consumer's own rbac() and networkPolicy()
  // compose with — rather than clobber — this grant. The egress is best-effort on
  // vanilla NetworkPolicy (it cannot name the apiserver, so it allows the given
  // TCP ports to any destination); operators on Calico/Cilium can tighten it.
  apiServerClient(rules, ports=[443, 6443]):: {
    config+:: {
      requiredRbac+: rules,
      requiredEgress+: [{ ports: [{ protocol: 'TCP', port: port } for port in ports] }],
    },
  },

  // Security escape hatches — each downgrades one default for a workload that
  // genuinely needs it. The kurly.security.* mixins relax whole PSS profiles.
  rootUser():: { config+:: { runAsNonRoot: false } },
  writableRootFilesystem():: { config+:: { readOnlyRootFilesystem: false } },
  hostUsers():: { config+:: { hostUsers: true } },
}
