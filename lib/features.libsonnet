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
{
  // Container basics.
  image(image):: { config+:: { image: image } },
  port(port):: { config+:: { port: port } },
  // A port beside the primary `http` one, for a workload that listens on more
  // than one (a mail server's SMTP + web UI, a game server's TCP + UDP, a second
  // admin port). Composable several times — each call appends. `name` is the
  // shared identity of the container port and its Service port (≤15 chars,
  // lowercase, per the Kubernetes port-name rules); servicePort defaults to the
  // container port. expose=false keeps the port on the pod but off the Service
  // (a metrics port scraped in-cluster). protocol is 'TCP' or 'UDP'.
  extraPort(name, port, servicePort=null, protocol='TCP', appProtocol=null, expose=true):: {
    config+:: {
      extraPorts+: [{
        name: name,
        containerPort: port,
        servicePort: if servicePort == null then port else servicePort,
        protocol: protocol,
        appProtocol: appProtocol,
        expose: expose,
      }],
    },
  },
  replicas(replicas):: { config+:: { replicas: replicas } },
  // args appends arguments to the image's own entrypoint (a subcommand
  // selecting the workload); command overrides the entrypoint itself.
  args(args):: { config+:: { args: args } },
  command(command):: { config+:: { command: command } },
  env(env):: { config+:: { env+: env } },
  // Pull every key of a Secret into the container environment as env vars — for
  // apps that read their configuration, secrets included, from the environment
  // (envFrom secretRef) rather than files. kurly mints no Secret; the consumer
  // provides it. An optional prefix is prepended to each key's variable name.
  envFromSecret(secretName, prefix=''):: {
    config+:: { envFrom+: [{ secretRef: { name: secretName } } + (if prefix == '' then {} else { prefix: prefix })] },
  },
  // The ConfigMap equivalent — non-secret configuration read from the environment.
  envFromConfigMap(configMapName, prefix=''):: {
    config+:: { envFrom+: [{ configMapRef: { name: configMapName } } + (if prefix == '' then {} else { prefix: prefix })] },
  },
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
  // runtimeClassName picks the sandbox the pod runs under (gVisor, Kata). The
  // class names are the cluster's, so kurly cannot default one.
  runtimeClassName(runtimeClassName):: { config+:: { runtimeClassName: runtimeClassName } },
  resources(requests=null, limits=null):: {
    config+:: {
      resources+:
        (if requests == null then {} else { requests: requests })
        + (if limits == null then {} else { limits: limits }),
    },
  },
  // reserve sets a reservation from given quantities. It replaced five named sizes
  // (nano/micro/small/medium/large), which were removed once their only consumer
  // stopped pricing from them: a consumer whose customers choose CPU and memory
  // directly produces pairs no name can express — 370m and 608Mi — and rounding
  // such an order to the nearest name would run a tenant on a reservation they did
  // not buy while billing them for the one they did.
  //
  // It applies the SAME limit policy as the presets, deliberately: the memory limit
  // equals the memory request, and there is no CPU limit. Equal memory request and
  // limit makes the pod Guaranteed for memory, so it is not evicted for exceeding
  // its request — which is what lets an OOM kill be read as a statement about this
  // workload rather than about whatever else shared its node. No CPU limit because
  // throttling is usually worse than letting a pod burst.
  //
  // Replaces the resources wholesale, so compose it BEFORE any single-knob
  // resources() tweak. Applies to the workload's container; a stage
  // running more than one has no defined answer here, and splitting a total between
  // containers is a question for whoever knows how the work divides.
  reserve(cpu, memory):: {
    config+:: {
      resources: {
        requests: { cpu: cpu, memory: memory },
        limits: { memory: memory },
      },
    },
  },
  // The Service's port — the contract with clients, not with the container.
  servicePort(port):: { config+:: { servicePort: port } },
  // Its type. LoadBalancer and NodePort exist only where the cluster provides
  // them, so kurly names none.
  serviceType(type):: { config+:: { serviceType: type } },
  // Annotations on the Service. A cloud load balancer is configured through
  // these and nothing else, and the keys differ per provider — kurly cannot know
  // them, and a Service that cannot carry them cannot be a working LoadBalancer.
  serviceAnnotations(annotations):: { config+:: { serviceAnnotations+: annotations } },
  // The IP families every Service kurly renders should ask for. A cluster is
  // single-stack IPv4, single-stack IPv6, or dual-stack; pinning the family it
  // does not have gets the Service rejected, so there is no default.
  ipFamilies(families, policy=null):: {
    config+:: {
      ipFamilies: families,
      [if policy != null then 'ipFamilyPolicy']: policy,
    },
  },
  serviceAccount(serviceAccountName):: { config+:: { serviceAccountName: serviceAccountName } },
  // Annotations for the ServiceAccount kurly mints for a workload that declares
  // RBAC — the usual home of cloud workload identity. Bringing your own account
  // with kurly.serviceAccount() instead makes this moot: kurly then mints none.
  serviceAccountAnnotations(annotations):: { config+:: { serviceAccountAnnotations+: annotations } },
  // HTTP readiness+liveness probes on the named `http` port.
  probes(path='/healthz'):: { config+:: { probePath: path } },
  // Explicit probe specs (exec, tcpSocket, httpGet, …) that override the default
  // http probes — passed through verbatim.
  readinessProbe(probe):: { config+:: { readinessProbe: probe } },
  livenessProbe(probe):: { config+:: { livenessProbe: probe } },
  startupProbe(probe):: { config+:: { startupProbe: probe } },
  // Suppresses the legacy {SVCNAME}_SERVICE_* environment variables Kubernetes
  // injects — needed by apps that read their own NAME-prefixed env as config (a
  // Service named after the app then collides with its configuration keys).
  disableServiceLinks():: { config+:: { enableServiceLinks: false } },
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
  // shutdown sets the two halves of a graceful stop TOGETHER, because setting
  // either alone is how a rolling update drops requests.
  //
  // What actually happens when a pod goes away: its removal from the Service
  // endpoints and the SIGTERM to its container are dispatched CONCURRENTLY, and
  // neither waits for the other. Every proxy in the cluster has to hear about
  // the endpoint change and stop sending new connections — which takes as long
  // as it takes — while the application has already been told to stop. Requests
  // arriving in that window reach a process that is shutting down.
  //
  //   drain  seconds to do nothing after the pod is doomed and before SIGTERM
  //          is sent. That is the whole trick: the container keeps serving while
  //          the endpoint removal propagates, and only then is it asked to stop.
  //   grace  seconds the kubelet waits after SIGTERM before SIGKILL.
  //
  // THE DRAIN IS SPENT OUT OF THE GRACE PERIOD, not added to it. Both clocks
  // start when the pod is marked for deletion, so `drain` seconds of a `grace`
  // second budget are gone before the application is even told to stop. Set them
  // equal and it is killed with no time to finish anything, which is the exact
  // opposite of what somebody configuring a graceful shutdown intended — so
  // that composition is refused rather than rendered.
  //
  // The drain uses Kubernetes' NATIVE sleep handler rather than
  // `exec: ["/bin/sh", "-c", "sleep N"]`. On a distroless or scratch image there
  // is no shell and no sleep binary, so the exec form fails — and a failed
  // preStop hook does not stop the shutdown or raise anything a person sees. You
  // would get no drain, no error, and a rollout that quietly drops connections.
  // Any distroless or FROM-scratch image is in that position, and the native
  // handler is correct for every image regardless, so there is no reason to
  // reach for the shell form at all.
  //
  // `preStop` replaces the sleep with a verbatim handler, for an application
  // that needs to be told to quiesce rather than merely waited for.
  shutdown(drain=null, grace=null, preStop=null)::
    assert drain == null || grace == null || drain < grace :
           'kurly.shutdown: drain=%s is spent out of grace=%s, not added to it — leaving the workload %s seconds to stop. Give it a grace period longer than the drain.'
           % [drain, grace, grace - drain];
    assert drain == null || preStop == null :
           'kurly.shutdown: a container has one preStop handler — pass either a drain (which becomes a sleep) or a preStop of your own, not both';
    {
      config+::
        (if grace == null then {} else { terminationGracePeriodSeconds: grace })
        + (
          if drain != null then { lifecycle+: { preStop: { sleep: { seconds: drain } } } }
          else if preStop != null then { lifecycle+: { preStop: preStop } }
          else {}
        ),
    },
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
  //
  // store may be composed more than once — each call adds a DISTINCT PVC at its own
  // mount path, for an app that keeps data in several directories. The first store
  // keeps the historical names (volume 'store', PVC '<name>-store'); the rest are
  // named after their mount path.
  store(mountPath, size, accessModes=['ReadWriteOnce'], storageClass=null, selector={}, annotations={}):: {
    config+:: {
      stores+: [{
        mountPath: mountPath,
        size: size,
        accessModes: accessModes,
        storageClass: storageClass,
        selector: selector,
        annotations: annotations,
      }],
    },
  },
  // Renders a ConfigMap from a filename->content map and mounts it read-only. By
  // default the whole ConfigMap mounts as a DIRECTORY at mountPath (replacing
  // whatever is there). With subPath=true each file is instead mounted
  // INDIVIDUALLY at mountPath/<filename> via a subPath mount, so a single config
  // file drops into a directory the image already populates (e.g. an app's
  // config.json beside its assets) without shadowing the rest — the standard
  // Kubernetes single-file-mount pattern. (A subPath mount does not receive later
  // ConfigMap updates, which is the accepted trade-off for config read at startup.)
  config(files, mountPath='/etc/config', subPath=false):: {
    config+:: { configFiles: { mountPath: mountPath, files: files, subPath: subPath } },
  },
  // Mounts a Secret the consumer provides. By default the whole Secret mounts as a
  // DIRECTORY at mountPath, replacing whatever the image put there.
  //
  // `subPath` names ONE key and mounts it as a single FILE at mountPath, leaving
  // the directory around it intact — the same shape kurly.config offers, and
  // needed for the same reason: an application that reads a credential from a
  // fixed path inside its own install tree cannot have that tree shadowed. It is
  // also how such a file survives a restart when the application would otherwise
  // GENERATE one (a Django SECRET_KEY written beside the code, regenerated on
  // every boot and silently invalidating every session).
  //
  // A subPath mount does not receive later Secret updates. For a value read once
  // at startup that is the accepted trade-off; for one that rotates, mount the
  // directory instead.
  secretMount(secretName, mountPath, readOnly=true, optional=false, defaultMode=null, subPath=null):: {
    config+:: {
      secretMounts+: [{
        secretName: secretName,
        mountPath: mountPath,
        readOnly: readOnly,
        optional: optional,
        defaultMode: defaultMode,
        subPath: subPath,
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
  // networkPolicy is the low-level Kubernetes variant of the kurly.network axis:
  // it takes verbatim networking.k8s.io/v1 ingress/egress rules. For an
  // allow-list written in the neutral vocabulary (and the Calico/Cilium
  // variants), reach for kurly.network.* instead; both feed the same slot and
  // share the `networkPolicy` exclusion group, so a workload firewalls one way.
  networkPolicy(ingress=[], egress=[], policyTypes=null):: {
    config+:: {
      networkPolicy: {
        variant: 'kubernetes',
        allowFrom: [],
        allowTo: [],
        ingress: ingress,
        egress: egress,
        policyTypes: policyTypes,
        extraSpec: {},
      },
      exclusive+: { networkPolicy+: ['kubernetes'] },
    },
  },
  serviceMonitor(port='http', path='/metrics', interval=null):: {
    config+:: { serviceMonitor: { port: port, path: path, interval: interval } },
  },
  // alerts writes a PrometheusRule of rules bound to THIS workload's objects.
  // The PromQL is the easy half; the hard half is the selectors, and kurly named
  // every object they have to match — the controller, the container, each claim.
  //
  // Rules that cannot fire are never emitted: no memory rule without a memory
  // limit to breach, no storage rule without a claim to fill, and no
  // availability rule for a controller kind that has no ready-versus-desired
  // metric pair. A rule that cannot fire reads as coverage and is not.
  //
  //   namespace  scopes every expression. Leave it null ONLY if the Prometheus
  //              scraping these sets enforcedNamespaceLabel, which rewrites
  //              rules to their own namespace — without either, a rule matches
  //              this workload's name in EVERY namespace, which is the quiet
  //              failure this argument exists to prevent.
  //   for        how long the condition must hold. An SLO, so it is yours.
  //   storageFull / memoryPressure  percentages, null to skip.
  //   runbooks   base URL of your book repository. Each rule already names the
  //              gumshoe book that investigates or fixes it (as `runbook`, the
  //              command to run); giving a base turns that into the
  //              `runbook_url` an Alertmanager UI links. Absent by default,
  //              because where your books live is not kurly's to assume.
  //   rules      verbatim extra rules, appended — for everything above, which is
  //              every alert that depends on what the application MEANS rather
  //              than on whether it is running.
  alerts(
    namespace=null,
    severity='warning',
    for_='10m',
    unavailable=true,
    crashLooping=true,
    storageFull=85,
    memoryPressure=90,
    runbooks=null,
    labels={},
    annotations={},
    rules=[],
  ):: {
    config+:: {
      alerts: {
        namespace: namespace,
        severity: severity,
        'for': for_,
        unavailable: unavailable,
        crashLooping: crashLooping,
        storageFull: storageFull,
        memoryPressure: memoryPressure,
        runbooks: runbooks,
        labels: labels,
        annotations: annotations,
        rules: rules,
      },
    },
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
  // Allow the process to gain privileges its parent lacks — required to exec a
  // binary that carries file capabilities (e.g. an image whose entrypoint has
  // cap_net_bind_service set), which the default noNewPrivileges posture blocks.
  allowPrivilegeEscalation():: { config+:: { allowPrivilegeEscalation: true } },
  // Keep the container runtime's default Linux capabilities instead of dropping
  // ALL — the way an app that binds a privileged port (<1024) as root keeps
  // CAP_NET_BIND_SERVICE.
  keepCapabilities():: { config+:: { dropAllCapabilities: false } },
  // Grant named Linux capabilities on top of the dropped-ALL default — the way an
  // app that needs a specific privilege (a DNS server binding :53 and managing
  // routes wants NET_BIND_SERVICE and NET_ADMIN) keeps the hardened posture for
  // everything else. Composes with the drop: the capabilities are added back
  // explicitly, so the manifest states exactly which privileges the app holds.
  addCapabilities(capabilities):: { config+:: { addCapabilities: capabilities } },

  // Extra group memberships for every container in the pod — the way to reach
  // storage owned by a fixed GID the pod does not run as (a shared NFS/CephFS
  // export whose files are group-owned). Distinct from fsGroup, which changes
  // the ownership of the pod's OWN volumes; these grant access to groups that
  // already exist.
  supplementalGroups(groups):: { config+:: { supplementalGroups: groups } },

  // Pod name resolution: a resolver policy, extra nameservers/searches/options,
  // and static /etc/hosts entries for names no DNS serves. dnsPolicy 'None'
  // replaces the pod's resolv.conf wholesale, so it MUST bring its own
  // nameservers — the apiserver rejects the pod otherwise, which this catches at
  // render.
  dns(policy=null, config=null, hostAliases=[])::
    assert policy != 'None' || (config != null && std.length(std.get(config, 'nameservers', [])) > 0) :
           "kurly.dns: dnsPolicy 'None' needs config.nameservers — with no resolver the pod is rejected. "
           + 'Pass config={ nameservers: [ … ] }, or use a different dnsPolicy.';
    {
      config+:: std.prune({
        dnsPolicy: policy,
        dnsConfig: config,
        hostAliases: if hostAliases == [] then null else hostAliases,
      }),
    },
}
