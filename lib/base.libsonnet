// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The shared core of every kurly workload: a hidden config object and the
// manifest fields computed from it. A base kind (http/worker/cron/daemon)
// composes this; features (kurly.store, kurly.expose.gateway, …) are mixins
// merged on with `+`, each contributing to `config` so the computed manifests
// late-bind regardless of compose order. The visible fields of the result ARE
// the manifests.
local k = import './k.libsonnet';

// A volume name derived from a mount path: '/var/lib/tik' -> 'var-lib-tik'.
// Keeps generated volume names DNS-1123 and unique per distinct mount path.
local volumeName(path) = std.strReplace(std.lstripChars(path, '/'), '/', '-');

// The PersistentVolumeClaim backing a store, and the ConfigMap holding a
// workload's config files, are written as plain manifests (like the expose
// recipes) so the render-time dependency closure stays at k8s-libsonnet alone.
local pvcManifest(name, spec, labels) = {
  apiVersion: 'v1',
  kind: 'PersistentVolumeClaim',
  metadata: { name: name, labels: labels }
            + (if spec.annotations == {} then {} else { annotations: spec.annotations }),
  spec: {
          accessModes: spec.accessModes,
          resources: { requests: { storage: spec.size } },
        } + (if spec.storageClass == null then {} else { storageClassName: spec.storageClass })
        + (if spec.selector == {} then {} else { selector: spec.selector }),
};

local configMapManifest(name, files, labels) = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: name, labels: labels },
  data: files,
};

// The owned manifests a feature can add beyond the pod controller — each written
// as a plain manifest (like the PVC/ConfigMap above and the expose recipes) so
// the render-time dependency closure stays at k8s-libsonnet alone, and so CRD
// kinds k8s-libsonnet does not model (ServiceMonitor) render the same way. Each
// selects the workload's own pods by its stable selectorLabels.
local pdbManifest(name, spec, selectorLabels, labels) = std.prune({
  apiVersion: 'policy/v1',
  kind: 'PodDisruptionBudget',
  metadata: { name: name, labels: labels },
  spec: {
    selector: { matchLabels: selectorLabels },
    minAvailable: spec.minAvailable,
    maxUnavailable: spec.maxUnavailable,
  },
});

local hpaManifest(name, spec, labels) = {
  apiVersion: 'autoscaling/v2',
  kind: 'HorizontalPodAutoscaler',
  metadata: { name: name, labels: labels },
  spec: {
    scaleTargetRef: { apiVersion: 'apps/v1', kind: 'Deployment', name: name },
    minReplicas: spec.minReplicas,
    maxReplicas: spec.maxReplicas,
    metrics:
      local utilization(resource, target) =
        { type: 'Resource', resource: { name: resource, target: { type: 'Utilization', averageUtilization: target } } };
      (if spec.targetCPU == null then [] else [utilization('cpu', spec.targetCPU)])
      + (if spec.targetMemory == null then [] else [utilization('memory', spec.targetMemory)]),
  },
};

local networkPolicyManifest(name, spec, selectorLabels, labels) = std.prune({
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: { name: name, labels: labels },
  spec: {
    podSelector: { matchLabels: selectorLabels },
    policyTypes: spec.policyTypes,
    ingress: spec.ingress,
    egress: spec.egress,
  },
});

// A headless Service (clusterIP: None) selecting the workload's pods, for
// peer discovery by DNS. publishNotReadyAddresses lists pods before they are
// Ready, so peers stay discoverable across a rollout.
local headlessServiceManifest(name, spec, selectorLabels, labels) = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: { name: name + '-headless', labels: labels },
  spec: std.prune({
    clusterIP: 'None',
    selector: selectorLabels,
    publishNotReadyAddresses: (if spec.publishNotReadyAddresses then true else null),
    ports: (if spec.port == null then null else [{ name: 'tcp', port: spec.port, targetPort: spec.port }]),
  }),
};

local serviceMonitorManifest(name, spec, selectorLabels, labels) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: { name: name, labels: labels },
  spec: {
    selector: { matchLabels: selectorLabels },
    endpoints: [std.prune({ port: spec.port, path: spec.path, interval: spec.interval })],
  },
};

// A namespaced Role and the RoleBinding tying it to the identity the pod runs
// under, plus the ServiceAccount itself when kurly is the one creating it.
//
// The binding follows the RESOLVED account rather than the workload's name: a
// consumer who brings their own ServiceAccount is usually doing it to carry an
// annotation kurly cannot know — an IRSA role ARN, a GKE or Azure workload
// identity — and a grant bound to some other account would leave the pod without
// the rules the workload needs. When they bring one, kurly does not mint a
// second: the account is theirs to own.
local rbacManifests(name, spec, labels, account, mint, accountAnnotations) =
  (
    if !mint then []
    else [{
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: { name: account, labels: labels }
                + (if accountAnnotations == {} then {} else { annotations: accountAnnotations }),
    }]
  )
  + [
    { apiVersion: 'rbac.authorization.k8s.io/v1', kind: 'Role', metadata: { name: name, labels: labels }, rules: spec.rules },
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: { name: name, labels: labels },
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: name },
      subjects: [{ kind: 'ServiceAccount', name: account }],
    },
  ];

// The exclusion groups a config has composed conflicting members into: a map
// of group name -> the feature names that claimed it. A group with more than
// one distinct member is a composition error (e.g. two exposure recipes).
local exclusionConflicts(exclusive) = [
  group
  for group in std.objectFields(exclusive)
  if std.length(std.set(exclusive[group])) > 1
];

{
  // core carries everything common to all workload kinds.
  core(name, image):: {
    // Late-bound handle on the composed app object, for fields whose value is
    // a nested object literal (where a bare `self` would bind to the literal).
    local this = self,

    // A feature that must not co-occur with another adds its name under a
    // shared group here (config+:: { exclusive+: { exposure+: ['gateway'] } });
    // composing a second member of the same group fails the render below.
    assert exclusionConflicts(this.config.exclusive) == [] :
           'kurly: conflicting features composed — only one member of each exclusive group is allowed. Conflicts: '
           + std.join('; ', [
      group + ' (' + std.join(' + ', this.config.exclusive[group]) + ')'
      for group in exclusionConflicts(this.config.exclusive)
    ]),

    // Asking for uid 0 while promising the kubelet a non-root user is a pod that
    // never starts: admission accepts it and the kubelet then refuses the
    // container with "has runAsNonRoot and image will run as root". The two knobs
    // are set by different features (runAs and the security profiles), so the
    // contradiction usually arrives by composition rather than on purpose —
    // which is why it is asserted here, against the MERGED config, rather than
    // in whichever feature was written last.
    assert !(this.config.runAsNonRoot && this.config.runAsUser == 0) :
           'kurly: runAsUser 0 contradicts runAsNonRoot — the kubelet refuses the container before it starts. '
           + 'Run as a non-zero uid, or compose kurly.rootUser() (or kurly.security.baseline/privileged) to drop the non-root requirement.',

    config:: {
      name: name,
      image: image,
      port: null,
      command: [],
      args: [],
      env: {},
      // The workload version, stamped as app.kubernetes.io/version. Left null
      // by default; a workload sets it from its `version` constant (which the
      // release pipeline rewrites from 'dev' to the calver).
      version: null,
      labels: {},
      annotations: {},
      resources: { requests: { cpu: '100m', memory: '128Mi' } },
      serviceAccountName: null,
      // Annotations for the ServiceAccount kurly mints — where cloud workload
      // identity is wired (eks.amazonaws.com/role-arn, iam.gke.io/…). Ignored
      // when the consumer brings their own account, which is theirs to annotate.
      serviceAccountAnnotations: {},
      probePath: null,
      // Probes and container lifecycle. probePath renders the default http
      // readiness+liveness probes; readinessProbe/livenessProbe are full probe
      // specs (exec, tcpSocket, …) that override it when set. lifecycle carries
      // postStart/preStop handlers, initContainers a list of extra containers
      // that run before the main one — all passed through verbatim.
      readinessProbe: null,
      livenessProbe: null,
      lifecycle: {},
      initContainers: [],
      // Extra containers beside the workload's own. Like initContainers they are
      // passed through, but both inherit containerSecurity first.
      sidecars: [],
      terminationGracePeriodSeconds: null,
      // A headless Service ({ port, publishNotReadyAddresses }) selecting the
      // workload's pods, for peer discovery by DNS (clusterIP: None).
      headlessService: null,
      // RollingUpdate tuning ({ maxSurge, maxUnavailable }); with strategy
      // 'RollingUpdate' it lets a new pod surge alongside the old.
      rollingUpdate: null,
      // Exclusion-group membership (group name -> [feature names]); asserted above.
      exclusive: {},
      // Storage and mounts. A workload has at most one store (its owned PVC)
      // and one config bundle (its owned ConfigMap); secret mounts and scratch
      // volumes are lists because a workload may need several of each. Every
      // slot is empty by default, so a stateless workload renders exactly as a
      // bare kind. Names: the store's PVC is `<name>-store`, the config's
      // ConfigMap is `<name>-config`; in-pod volume names derive from the mount
      // path (secret volumes from the Secret name).
      store: null,  // { mountPath, size, accessModes, storageClass, selector, annotations }
      configFiles: null,  // { mountPath, files }
      secretMounts: [],  // [{ secretName, mountPath, readOnly, optional, defaultMode }]
      scratch: [],  // [{ mountPath, sizeLimit }]
      // Deployment update strategy ('Recreate' for a single-writer workload on
      // a ReadWriteOnce store, where a rolling update would deadlock on the
      // volume). null leaves the Kubernetes default (RollingUpdate).
      strategy: null,
      // Pod scheduling. Each is passed to the pod template verbatim (kurly does
      // not model the Kubernetes schema, which would drift): a node-label map, a
      // toleration list, a topology-spread-constraint list, and an affinity
      // object. Empty slots render nothing, so a workload with no scheduling
      // constraints is untouched.
      nodeSelector: {},
      tolerations: [],
      topologySpread: [],
      affinity: {},
      // Pod-template extras. podLabels/podAnnotations land on the pod template
      // ONLY (never the workload metadata, never the selector) — for network
      // policies, log collection, sidecar injection. imagePullSecrets and
      // priorityClassName go on the pod spec. Empty slots render nothing.
      podLabels: {},
      podAnnotations: {},
      imagePullSecrets: [],
      priorityClassName: null,
      // Owned manifests a feature adds beyond the pod controller (null/absent by
      // default). rbac additionally makes the pod run under the ServiceAccount it
      // creates (podServiceAccount below).
      pdb: null,  // { minAvailable, maxUnavailable }
      hpa: null,  // { minReplicas, maxReplicas, targetCPU, targetMemory }
      networkPolicy: null,  // { ingress, egress, policyTypes }
      serviceMonitor: null,  // { port, path, interval }
      rbac: null,  // { rules }
      // Cross-cutting requirements a capability declares so the manifest that
      // owns the concern honors them without the capabilities reaching into each
      // other — they meet here in config. requiredRbac accumulates Role rules the
      // rbac manifests union in (so a feature's grant survives a consumer's own
      // rbac()); requiredEgress accumulates NetworkPolicy egress rules the policy
      // manifest always allows (so a consumer's networkPolicy() cannot cut off a
      // sidecar's apiserver access). A non-empty requiredRbac also mints the
      // ServiceAccount even when the consumer never calls rbac().
      requiredRbac: [],  // [ {apiGroups, resources, verbs}, … ]
      requiredEgress: [],  // [ egress rule, … ]
      // Security knobs, defaulting to the Pod Security Standards `restricted`
      // profile plus extra hardening (read-only root filesystem, user
      // namespaces). Feature functions relax them (one knob, or a whole profile
      // via kurly.security.*). A relaxed knob omits its field from the manifest
      // rather than writing the Kubernetes default explicitly.
      runAsNonRoot: true,
      runAsUser: null,
      runAsGroup: null,
      fsGroup: null,
      seccompProfile: 'RuntimeDefault',
      allowPrivilegeEscalation: false,
      dropAllCapabilities: true,
      readOnlyRootFilesystem: true,
      hostUsers: false,
    },

    // Selector labels feed immutable matchLabels fields, so they stay minimal
    // and stable — user labels must never leak in here.
    selectorLabels:: { 'app.kubernetes.io/name': this.config.name },

    labels:: self.selectorLabels {
      'app.kubernetes.io/managed-by': 'kurly',
    } + (
      if this.config.version == null
      then {}
      else { 'app.kubernetes.io/version': this.config.version }
    ) + self.config.labels,

    // The volume/mount plumbing, computed once from config so the container
    // (mounts) and the pod template (volumes) stay in lockstep, and the owned
    // PVC/ConfigMap surface as manifests. Every source contributes a matching
    // (volume, mount) pair keyed on the same name.
    local storeName = this.config.name + '-store',
    local configName = this.config.name + '-config',

    volumeMounts::
      local cfg = this.config;
      (if cfg.store == null then [] else [{ name: 'store', mountPath: cfg.store.mountPath }])
      + (if cfg.configFiles == null then [] else [{ name: 'config', mountPath: cfg.configFiles.mountPath, readOnly: true }])
      + [{ name: m.secretName, mountPath: m.mountPath, readOnly: m.readOnly } for m in cfg.secretMounts]
      + [{ name: volumeName(s.mountPath), mountPath: s.mountPath } for s in cfg.scratch],

    volumes::
      local cfg = this.config;
      (if cfg.store == null then [] else [{ name: 'store', persistentVolumeClaim: { claimName: storeName } }])
      + (if cfg.configFiles == null then [] else [{ name: 'config', configMap: { name: configName } }])
      + [
        { name: m.secretName, secret: std.prune({
          secretName: m.secretName,
          optional: if m.optional then true else null,
          defaultMode: m.defaultMode,
        }) }
        for m in cfg.secretMounts
      ]
      + [
        { name: volumeName(s.mountPath), emptyDir: (if s.sizeLimit == null then {} else { sizeLimit: s.sizeLimit }) }
        for s in cfg.scratch
      ],

    // The manifests a workload owns beyond its pod controller, exposed as named
    // handles so an author can place each into a stage: the store's PVC and the
    // config's ConfigMap (null when the workload has neither).
    storeClaim::
      if this.config.store == null then null else pvcManifest(storeName, this.config.store, this.labels),
    configMap::
      if this.config.configFiles == null then null else configMapManifest(configName, this.config.configFiles.files, this.labels),
    pdb::
      if this.config.pdb == null then null else pdbManifest(this.config.name, this.config.pdb, this.selectorLabels, this.labels),
    hpa::
      if this.config.hpa == null then null else hpaManifest(this.config.name, this.config.hpa, this.labels),
    // The NetworkPolicy always allows the requiredEgress a sidecar declared (e.g.
    // apiserver access), unioned into the consumer's egress; when that adds egress
    // to an otherwise ingress-only policy, Egress joins policyTypes so the rules
    // take effect (a null policyTypes lets Kubernetes infer it from the fields).
    networkPolicy::
      if this.config.networkPolicy == null then null else
        local np = this.config.networkPolicy;
        local egress = np.egress + this.config.requiredEgress;
        local policyTypes =
          if np.policyTypes != null && this.config.requiredEgress != [] && !std.member(np.policyTypes, 'Egress')
          then np.policyTypes + ['Egress'] else np.policyTypes;
        networkPolicyManifest(this.config.name, np { egress: egress, policyTypes: policyTypes }, this.selectorLabels, this.labels),
    serviceMonitor::
      if this.config.serviceMonitor == null then null else serviceMonitorManifest(this.config.name, this.config.serviceMonitor, this.selectorLabels, this.labels),
    headlessService::
      if this.config.headlessService == null then null else headlessServiceManifest(this.config.name, this.config.headlessService, this.selectorLabels, this.labels),
    // The Role's rules are the consumer's rbac() grant (if any) plus every
    // requiredRbac rule a capability declared, so a feature's grant survives a
    // consumer calling rbac() and neither clobbers the other.
    rbacRules::
      (if this.config.rbac == null then [] else this.config.rbac.rules) + this.config.requiredRbac,
    // rbac contributes THREE manifests (ServiceAccount, Role, RoleBinding),
    // minted whenever any rule exists — an explicit rbac() or a requiredRbac.
    rbacManifests::
      if this.rbacRules == [] then []
      else rbacManifests(
        this.config.name,
        { rules: this.rbacRules },
        this.labels,
        this.podServiceAccount,
        // Mint one only when the consumer did not bring their own.
        this.config.serviceAccountName == null,
        this.config.serviceAccountAnnotations,
      ),

    // The owned manifests as a list, hidden so it stays out of
    // std.objectValues(app); list() appends it explicitly.
    ownedManifests::
      std.filter(function(manifest) manifest != null, [
        this.storeClaim,
        this.configMap,
        this.pdb,
        this.hpa,
        this.networkPolicy,
        this.serviceMonitor,
        this.headlessService,
      ]) + this.rbacManifests,

    // The pod-level half of the security posture; each workload kind merges
    // this into its pod template spec. The container-level half lives in
    // `container`. hostUsers=false runs the pod in its own user namespace, so
    // even a container-breakout lands in an unprivileged host user. fsGroup is
    // set when a workload pins one — a non-root pod needs it to own a mounted
    // PersistentVolume's files. The ServiceAccount token is only mounted when a
    // ServiceAccount is explicitly configured — workloads that never talk to
    // the apiserver should not carry credentials for it.
    podSecurity::
      local cfg = this.config;
      local securityContext =
        (if cfg.runAsNonRoot then { runAsNonRoot: true } else {})
        + (
          if cfg.seccompProfile == null
          then {}
          else { seccompProfile: { type: cfg.seccompProfile } }
        )
        + (
          if cfg.fsGroup == null
          then {}
          else { fsGroup: cfg.fsGroup, fsGroupChangePolicy: 'OnRootMismatch' }
        );
      (if securityContext == {} then {} else { securityContext: securityContext })
      + { automountServiceAccountToken: this.podServiceAccount != null }
      + (if cfg.hostUsers then {} else { hostUsers: false }),

    // The ServiceAccount the pod runs under. A consumer's explicit choice wins:
    // they are usually bringing an account that carries an annotation kurly
    // cannot know (an IRSA role ARN, a GKE or Azure workload identity), and a
    // workload that declares RBAC used to override it silently — which made
    // cloud workload identity unusable on every such workload while the
    // manifests looked right. Otherwise, any Role rule (an explicit rbac() or a
    // capability's requiredRbac) means kurly mints one named after the workload.
    // The token is mounted only when this is set (see podSecurity).
    podServiceAccount::
      if this.config.serviceAccountName != null then this.config.serviceAccountName
      else if this.rbacRules != [] then this.config.name
      else null,

    // Pod-template metadata: the workload labels plus pod-only labels, and the
    // workload annotations plus pod-only annotations. The selector is unaffected
    // (it keys on selectorLabels alone), so pod labels never reach the immutable
    // field.
    podTemplateLabels:: this.labels + this.config.podLabels,
    podTemplateAnnotations:: this.config.annotations + this.config.podAnnotations,

    // Pod-spec extras every kind merges alongside podSecurity/podVolumes/
    // podScheduling: image-pull secrets, a priority class, and the resolved
    // ServiceAccount. Each is omitted when unset.
    podExtras::
      local cfg = this.config;
      (if cfg.imagePullSecrets == [] then {} else { imagePullSecrets: [{ name: s } for s in cfg.imagePullSecrets] })
      + (if cfg.priorityClassName == null then {} else { priorityClassName: cfg.priorityClassName })
      + (
        if cfg.initContainers == []
        then {}
        // The posture goes UNDER the container, so a spec that sets its own
        // securityContext still wins — but one that says nothing now follows the
        // consumer's uid instead of whatever the recipe's author had in mind.
        else {
          initContainers: [
            (if this.containerSecurity == {} then {} else { securityContext: this.containerSecurity }) + c
            for c in cfg.initContainers
          ],
        }
      )
      + (if cfg.terminationGracePeriodSeconds == null then {} else { terminationGracePeriodSeconds: cfg.terminationGracePeriodSeconds })
      + (if this.podServiceAccount == null then {} else { serviceAccountName: this.podServiceAccount }),

    // The volumes half of the pod template, kept alongside podSecurity so every
    // Deployment/CronJob/DaemonSet-backed kind merges the same fragment.
    podVolumes::
      if this.volumes == [] then {} else { volumes: this.volumes },

    // The scheduling half of the pod template — node selector, tolerations,
    // topology-spread constraints, and affinity — merged into the pod spec by
    // every kind alongside podSecurity and podVolumes. Each field is omitted
    // when its config slot is empty, so a workload with no constraints renders
    // no scheduling stanza at all.
    podScheduling::
      local cfg = this.config;
      (if cfg.nodeSelector == {} then {} else { nodeSelector: cfg.nodeSelector })
      + (if cfg.tolerations == [] then {} else { tolerations: cfg.tolerations })
      + (if cfg.topologySpread == [] then {} else { topologySpreadConstraints: cfg.topologySpread })
      + (if cfg.affinity == {} then {} else { affinity: cfg.affinity }),

    // The container-level security posture, derived from config so that EVERY
    // container in the pod can carry it — not just the workload's own. A recipe
    // that writes these fields as literals into an initContainer or a sidecar
    // puts them beyond reach of kurly.runAs() and the security profiles, and the
    // pod then half-obeys the composed posture: exactly what stops a workload
    // running where uids are not the consumer's to choose (OpenShift assigns an
    // arbitrary uid per namespace and rejects anything else).
    //
    // A relaxed knob omits its field rather than writing the Kubernetes default,
    // so security.privileged produces {} here and no container carries a
    // securityContext at all.
    containerSecurity::
      local cfg = self.config;
      std.prune({
        allowPrivilegeEscalation: if cfg.allowPrivilegeEscalation then null else false,
        readOnlyRootFilesystem: if cfg.readOnlyRootFilesystem then true else null,
        capabilities: if cfg.dropAllCapabilities then { drop: ['ALL'] } else null,
        runAsUser: cfg.runAsUser,
        runAsGroup: cfg.runAsGroup,
      }),

    // The workload's container followed by any sidecars, each inheriting the
    // composed security posture unless it carries its own. Every kind builds its
    // pod from this, so a sidecar is not a Deployment-only privilege.
    podContainers::
      local inherited = if this.containerSecurity == {} then {} else { securityContext: this.containerSecurity };
      [this.container] + [inherited + s for s in this.config.sidecars],

    container::
      local cfg = self.config;
      k.core.v1.container.new(cfg.name, cfg.image)
      + (
        if cfg.port == null
        then {}
        else k.core.v1.container.withPorts([k.core.v1.containerPort.newNamed(cfg.port, 'http')])
      )
      + (if cfg.command == [] then {} else k.core.v1.container.withCommand(cfg.command))
      + (if cfg.args == [] then {} else k.core.v1.container.withArgs(cfg.args))
      + k.core.v1.container.resources.withRequests(cfg.resources.requests)
      + (
        if std.objectHas(cfg.resources, 'limits')
        then k.core.v1.container.resources.withLimits(cfg.resources.limits)
        else {}
      )
      + (
        if cfg.env == {}
        then {}
        else k.core.v1.container.withEnv([
          k.core.v1.envVar.new(variable, cfg.env[variable])
          for variable in std.objectFields(cfg.env)
        ])
      )
      + (
        if self.volumeMounts == []
        then {}
        else k.core.v1.container.withVolumeMountsMixin(self.volumeMounts)
      )
      // Readiness/liveness: an explicit probe spec (exec, tcpSocket, …) wins;
      // otherwise probePath renders the default http probes on the named port.
      + (
        if cfg.readinessProbe != null then { readinessProbe: cfg.readinessProbe }
        else if cfg.probePath == null then {}
        else k.core.v1.container.readinessProbe.httpGet.withPath(cfg.probePath)
             + k.core.v1.container.readinessProbe.httpGet.withPort('http')
      )
      + (
        if cfg.livenessProbe != null then { livenessProbe: cfg.livenessProbe }
        else if cfg.probePath == null then {}
        else k.core.v1.container.livenessProbe.httpGet.withPath(cfg.probePath)
             + k.core.v1.container.livenessProbe.httpGet.withPort('http')
      )
      + (if cfg.lifecycle == {} then {} else { lifecycle: cfg.lifecycle })
      + (if this.containerSecurity == {} then {} else { securityContext: this.containerSecurity }),
  },

  // deployment adds the Deployment manifest plus a replica count knob. Composed
  // onto core by every Deployment-backed kind (http, worker).
  deployment:: {
    config+:: { replicas: 1 },

    deployment:
      local cfg = self.config;
      // Captured before the nested `spec+` literal, where `self` would rebind.
      local podSpec = self.podSecurity + self.podVolumes + self.podScheduling + self.podExtras;
      k.apps.v1.deployment.new(cfg.name, replicas=cfg.replicas, containers=self.podContainers, podLabels=self.selectorLabels)
      + k.apps.v1.deployment.metadata.withLabels(self.labels)
      + k.apps.v1.deployment.spec.template.metadata.withLabelsMixin(self.podTemplateLabels)
      + { spec+: { template+: { spec+: podSpec } } }
      + (
        if cfg.strategy == null
        then {}
        else { spec+: { strategy: { type: cfg.strategy } + (if cfg.rollingUpdate == null then {} else { rollingUpdate: cfg.rollingUpdate }) } }
      )
      + (if cfg.annotations == {} then {} else k.apps.v1.deployment.metadata.withAnnotations(cfg.annotations))
      + (
        if self.podTemplateAnnotations == {}
        then {}
        else k.apps.v1.deployment.spec.template.metadata.withAnnotations(self.podTemplateAnnotations)
      ),
  },

  // service adds a ClusterIP Service in front of the workload's named `http`
  // container port. Composed onto core by the HTTP-facing kind.
  service:: {
    service:
      local cfg = self.config;
      k.core.v1.service.new(cfg.name, self.selectorLabels, [k.core.v1.servicePort.newNamed('http', 80, 'http')])
      + k.core.v1.service.metadata.withLabels(self.labels),
  },
}
