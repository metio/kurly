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
      probePath: null,
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

    // The owned manifests as a list, hidden so it stays out of
    // std.objectValues(app); list() appends it explicitly.
    ownedManifests::
      std.filter(function(manifest) manifest != null, [this.storeClaim, this.configMap]),

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
      + { automountServiceAccountToken: cfg.serviceAccountName != null }
      + (if cfg.hostUsers then {} else { hostUsers: false }),

    // The volumes half of the pod template, kept alongside podSecurity so every
    // Deployment/CronJob/DaemonSet-backed kind merges the same fragment.
    podVolumes::
      if this.volumes == [] then {} else { volumes: this.volumes },

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
      + (
        if cfg.probePath == null
        then {}
        else
          k.core.v1.container.readinessProbe.httpGet.withPath(cfg.probePath)
          + k.core.v1.container.readinessProbe.httpGet.withPort('http')
          + k.core.v1.container.livenessProbe.httpGet.withPath(cfg.probePath)
          + k.core.v1.container.livenessProbe.httpGet.withPort('http')
      )
      + (
        if cfg.allowPrivilegeEscalation
        then {}
        else k.core.v1.container.securityContext.withAllowPrivilegeEscalation(false)
      )
      + (
        if cfg.readOnlyRootFilesystem
        then k.core.v1.container.securityContext.withReadOnlyRootFilesystem(true)
        else {}
      )
      + (
        if cfg.dropAllCapabilities
        then k.core.v1.container.securityContext.capabilities.withDrop(['ALL'])
        else {}
      )
      + (if cfg.runAsUser == null then {} else k.core.v1.container.securityContext.withRunAsUser(cfg.runAsUser))
      + (if cfg.runAsGroup == null then {} else k.core.v1.container.securityContext.withRunAsGroup(cfg.runAsGroup)),
  },

  // deployment adds the Deployment manifest plus a replica count knob. Composed
  // onto core by every Deployment-backed kind (http, worker).
  deployment:: {
    config+:: { replicas: 1 },

    deployment:
      local cfg = self.config;
      local podSecurity = self.podSecurity;
      local podVolumes = self.podVolumes;
      k.apps.v1.deployment.new(cfg.name, replicas=cfg.replicas, containers=[self.container], podLabels=self.selectorLabels)
      + k.apps.v1.deployment.metadata.withLabels(self.labels)
      + k.apps.v1.deployment.spec.template.metadata.withLabelsMixin(self.labels)
      + { spec+: { template+: { spec+: podSecurity + podVolumes } } }
      + (
        if cfg.strategy == null
        then {}
        else { spec+: { strategy: { type: cfg.strategy } } }
      )
      + (
        if cfg.annotations == {}
        then {}
        else
          k.apps.v1.deployment.metadata.withAnnotations(cfg.annotations)
          + k.apps.v1.deployment.spec.template.metadata.withAnnotations(cfg.annotations)
      )
      + (
        if cfg.serviceAccountName == null
        then {}
        else k.apps.v1.deployment.spec.template.spec.withServiceAccountName(cfg.serviceAccountName)
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
