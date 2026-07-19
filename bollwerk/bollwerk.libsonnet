// SPDX-FileCopyrightText: The Bollwerk Authors
// SPDX-FileCopyrightText: opencode.de IG BvC Richtlinien contributors
// SPDX-License-Identifier: Apache-2.0

// Bollwerk — the BSI IT-Grundschutz (APP.4.4 Kubernetes, SYS.1.6 Container)
// hardening baseline as NATIVE Kubernetes ValidatingAdmissionPolicies, no
// third-party admission engine required. It is a Jsonnet rendering of the
// Kyverno `validate.cel` policies from
// https://gitlab.opencode.de/ig-bvc/policy-entwicklung/richtlinien-umsetzung-kyverno
// (Apache-2.0): the CEL transfers verbatim into VAP `validations`; only the
// wrapper changes (match → matchConstraints, validationFailureAction → the
// binding's validationActions).
//
// One improvement over the source: the pod-spec is located by SHAPE, not by
// `object.kind`. Built-in objects carry no TypeMeta in the CEL `object` under
// native VAP, so `object.kind == "Pod"` is unreliable there — `has(spec.jobTemplate)`
// (CronJob), `has(spec.template)` (controller), else a bare Pod, is robust.
//
//   local bollwerk = import 'bollwerk/bollwerk.libsonnet';
//   bollwerk.list                              // every policy + binding as a List
//   bollwerk.policies['015-disallow-privileged-containers']   // one [VAP, Binding]

{
  // The registries an image may be pulled from (policy 004). The BSI source pins
  // its single private registry; this is a hidden field so a consumer overrides
  // it for their environment — `bollwerk { allowedRegistries:: [...] }`. The
  // default admits the public registries kurly's own workloads ship from, so
  // kurly manifests pass 004 unmodified; an opencode.de deployment overrides it
  // back to ['registry.opencode.de'].
  allowedRegistries:: [
    'docker.io',
    'ghcr.io',
    'quay.io',
    'registry.k8s.io',
    'gcr.io',
    'codeberg.org',
  ],

  // ---- shared matchConstraints resourceRules -----------------------------------
  local writeOps = ['CREATE', 'UPDATE'],

  // Every pod-bearing workload kind, grouped by apiGroup.
  workloadRules:: [
    { apiGroups: [''], apiVersions: ['v1'], operations: writeOps, resources: ['pods'] },
    { apiGroups: ['apps'], apiVersions: ['v1'], operations: writeOps, resources: ['deployments', 'daemonsets', 'statefulsets'] },
    { apiGroups: ['batch'], apiVersions: ['v1'], operations: writeOps, resources: ['jobs', 'cronjobs'] },
  ],

  // ---- shared CEL variables ----------------------------------------------------

  // The pod spec, located by SHAPE (robust in native VAP).
  podSpecVar:: {
    name: 'podSpec',
    expression: |||
      has(object.spec.jobTemplate) ? object.spec.jobTemplate.spec.template.spec :
      has(object.spec.template) ? object.spec.template.spec :
      object.spec
    |||,
  },

  // All containers (regular + init + ephemeral).
  containersVar:: {
    name: 'containers',
    expression: |||
      variables.podSpec.containers +
      (has(variables.podSpec.initContainers) ? variables.podSpec.initContainers : []) +
      (has(variables.podSpec.ephemeralContainers) ? variables.podSpec.ephemeralContainers : [])
    |||,
  },

  // Containers excluding initContainers — init containers exit before the pod
  // runs, so they carry no long-lived probes.
  containersNoInitVar:: {
    name: 'containers',
    expression: |||
      variables.podSpec.containers +
      (has(variables.podSpec.ephemeralContainers) ? variables.podSpec.ephemeralContainers : [])
    |||,
  },

  // ---- the constructor ---------------------------------------------------------
  // Builds a [ValidatingAdmissionPolicy, ValidatingAdmissionPolicyBinding] pair.
  // opts: { bsi: {requirement, protection, category}, resourceRules?, variables?,
  //         validations: [{expression, message}], action: 'Deny'|'Audit'|'Warn' }
  policy(id, name, opts):: [
    {
      apiVersion: 'admissionregistration.k8s.io/v1',
      kind: 'ValidatingAdmissionPolicy',
      metadata: {
        name: name,
        annotations: {
          'policies.opencode.de/ID': id,
          'policies.opencode.de/bsi-requirement': opts.bsi.requirement,
          'policies.opencode.de/bsi-protection-requirement': opts.bsi.protection,
          'policies.opencode.de/category': opts.bsi.category,
        },
      },
      spec: {
        failurePolicy: 'Fail',
        matchConstraints: { resourceRules: std.get(opts, 'resourceRules', $.workloadRules) },
      } + (
        local vars = std.get(opts, 'variables', []);
        if vars == [] then {} else { variables: vars }
      ) + {
        validations: opts.validations,
      },
    },
    {
      apiVersion: 'admissionregistration.k8s.io/v1',
      kind: 'ValidatingAdmissionPolicyBinding',
      metadata: { name: name },
      spec: {
        policyName: name,
        // The source's validationFailureAction becomes the binding's action:
        // Audit → [Audit] (report only), Enforce → [Deny].
        validationActions: [std.get(opts, 'action', 'Deny')],
      },
    },
  ],

  // ---- the policies ------------------------------------------------------------
  policies:: {
    '001-require-request-limits': $.policy('001', 'require-request-limits', {
      bsi: { requirement: 'SYS.1.6.A15', protection: 'standard', category: 'should' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
            has(container.resources) &&
            has(container.resources.requests) &&
            has(container.resources.requests.memory) &&
            has(container.resources.requests.cpu) &&
            has(container.resources.limits) &&
            has(container.resources.limits.memory))
        |||,
        message: 'CPU and memory resource requests and limits are required.',
      }],
    }),

    '003-restrict-latest-tag': $.policy('003', 'restrict-latest-tag', {
      bsi: { requirement: 'SYS.1.6.A7', protection: 'standard', category: 'should' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
            (
              container.image.endsWith(':latest') ||
              !container.image.contains(':')
            )
            ? container.?imagePullPolicy.orValue('') == 'Always' : true
          )
        |||,
        message: "The image tag ':latest' must only be used in combination with imagePullPolicy: Always.",
      }],
    }),

    // The source tests `has(container.image.registry)`, but under native VAP
    // `container.image` is a plain string with no `.registry` field — that
    // selection does not compile. kurly always writes fully-qualified image refs
    // (registry.example.com/repo:tag), so the robust native-VAP form is a string
    // prefix against the allowed-registry list.
    '004-restrict-image-registries': $.policy('004', 'restrict-image-registries', {
      bsi: { requirement: 'SYS.1.6.A6', protection: 'basic', category: 'must' },
      variables: [
        { name: 'allowedRegistries', expression: '[' + std.join(', ', ["'" + r + "'" for r in $.allowedRegistries]) + ']' },
        $.podSpecVar,
        $.containersVar,
      ],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
            variables.allowedRegistries.exists(registry,
              container.image.startsWith(registry + '/'))
          )
        |||,
        message: 'Unknown image registry.',
      }],
    }),

    '005-require-secrets-in-secret': $.policy('005', 'require-secrets-in-secret', {
      bsi: { requirement: 'SYS.1.6.A4', protection: 'standard', category: 'should' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [
        {
          expression: |||
            variables.containers.all(container,
              container.?env.orValue([]).all(env,
                !env.name.matches('(?i).*(secret|key|token|password|passwort|kennwort|user|nutzer).*')
                || has(env.valueFrom.secretKeyRef)
              )
            )
          |||,
          message: 'Environment variable names containing sensitive words must use secretKeyRef.',
        },
        {
          expression: |||
            variables.containers.all(container,
              container.?envFrom.orValue([]).all(envFrom,
                !envFrom.prefix.matches('(?i).*(secret|key|token|password|passwort|kennwort|user|nutzer).*')
                || has(envFrom.secretRef)
              )
            )
          |||,
          message: 'envFrom prefixes with sensitive words must refer to secrets.',
        },
        {
          expression: |||
            variables.podSpec.?volumes.orValue([]).all(volume,
              !volume.name.matches('(?i).*(secret|key|token|password|passwort|kennwort|user|nutzer).*')
              || has(volume.secret)
            )
          |||,
          message: 'Volume names with sensitive words must reference a secret.',
        },
      ],
    }),

    // Two matches (workloads + PersistentVolume) → two policies.
    '009-disallow-hostpath': $.policy('009', 'disallow-hostpath', {
      bsi: { requirement: 'SYS.1.6.A20', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar],
      action: 'Audit',
      validations: [{
        expression: 'variables.podSpec.?volumes.orValue([]).all(volume, size(volume) == 0 || !has(volume.hostPath))',
        message: 'HostPath volumes are forbidden. The field spec.volumes[*].hostPath must be unset',
      }],
    }),
    '009-disallow-hostpath-pv': $.policy('009', 'disallow-hostpath-pv', {
      bsi: { requirement: 'SYS.1.6.A20', protection: 'standard', category: 'must' },
      resourceRules: [{ apiGroups: [''], apiVersions: ['v1'], operations: writeOps, resources: ['persistentvolumes'] }],
      action: 'Audit',
      validations: [{
        expression: '!has(object.spec.hostPath) && !has(object.spec.local)',
        message: 'hostPath/local type persistent volumes are forbidden.',
      }],
    }),

    '012-require-ro-rootfs': $.policy('012', 'require-ro-rootfs', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'should' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
          container.?securityContext.?readOnlyRootFilesystem.orValue(false) == true)
        |||,
        message: 'Root filesystem must be read-only.',
      }],
    }),

    '013-require-run-as-nonroot': $.policy('013', 'require-run-as-nonroot', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          (has(variables.podSpec.securityContext) &&
            has(variables.podSpec.securityContext.runAsNonRoot) &&
            variables.podSpec.securityContext.runAsNonRoot == true &&
            variables.containers.all(c,
              c.?securityContext.?runAsNonRoot.orValue(true) == true)
            )
          ||
          variables.containers.all(c,
            has(c.securityContext) &&
            has(c.securityContext.runAsNonRoot) &&
            c.securityContext.runAsNonRoot == true)
        |||,
        message: 'Running as root is not allowed. Either the field spec.securityContext.runAsNonRoot or all of spec.containers[*].securityContext.runAsNonRoot, spec.initContainers[*].securityContext.runAsNonRoot and spec.ephemeralContainers[*].securityContext.runAsNonRoot, must be set to true.',
      }],
    }),

    '014-disallow-unwanted-capabilities': $.policy('014', 'disallow-unwanted-capabilities', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [
        { name: 'allowedCapabilities', expression: "['AUDIT_WRITE','CHOWN','DAC_OVERRIDE','FOWNER','FSETID','KILL','MKNOD','NET_BIND_SERVICE','SETFCAP','SETGID','SETPCAP','SETUID','SYS_CHROOT']" },
        $.podSpecVar,
        $.containersVar,
      ],
      action: 'Audit',
      validations: [
        {
          expression: |||
            variables.containers.all(container,
              container.?securityContext.?capabilities.?drop.orValue([]).size() > 0 &&
              container.?securityContext.?capabilities.?drop.orValue([]).exists(cap, cap.upperAscii() == 'ALL'))
          |||,
          message: "Capability drop must include 'ALL'.",
        },
        {
          expression: |||
            variables.containers.all(container,
              container.?securityContext.?capabilities.?add.orValue([]).all(capability, capability == '' || capability in variables.allowedCapabilities))
          |||,
          message: 'Any capabilities added beyond the allowed list (AUDIT_WRITE, CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, MKNOD, NET_BIND_SERVICE, SETFCAP, SETGID, SETPCAP, SETUID, SYS_CHROOT) are disallowed.',
        },
      ],
    }),

    '015-disallow-privileged-containers': $.policy('015', 'disallow-privileged-containers', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Deny',
      validations: [{
        expression: 'variables.containers.all(container, container.?securityContext.?privileged.orValue(false) == false)',
        message: 'Privileged mode is disallowed. All containers must set the securityContext.privileged field to `false` or unset the field.',
      }],
    }),

    '016-disallow-privilege-escalation': $.policy('016', 'disallow-privilege-escalation', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
          container.?securityContext.allowPrivilegeEscalation.orValue(true) == false)
        |||,
        message: 'Privilege escalation is disallowed. All containers must set the securityContext.allowPrivilegeEscalation field to `false`.',
      }],
    }),

    '017-require-run-as-non-root-user': $.policy('017', 'require-run-as-non-root-user', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [
        {
          expression: |||
            variables.containers.all(c,
              !(has(c.securityContext)) ||
              !(has(c.securityContext.runAsUser )) ||
              c.securityContext.runAsUser > 65535 )
          |||,
          message: 'Fehler: Jeder gesetzte runAsUser auf Container-Ebene muss größer als 65535 sein.',
        },
        {
          expression: |||
            !(has(variables.podSpec.securityContext.runAsUser)) ||
            !(has(variables.podSpec.securityContext)) ||
            variables.podSpec.securityContext.runAsUser > 65535 ||
            variables.containers.all(c,
              has(c.securityContext) &&
              has(c.securityContext.runAsUser) &&
              c.securityContext.runAsUser > 65535)
          |||,
          message: 'Fehler: Pod-Ebene runAsUser ≤ 65535 muss von allen Containern überschrieben werden.',
        },
      ],
    }),

    '018-require-non-root-groups': $.policy('018', 'require-non-root-groups', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [
        {
          expression: |||
            variables.containers.all(c,
              !(has(c.securityContext)) ||
              !(has(c.securityContext.runAsGroup )) ||
              c.securityContext.runAsGroup > 65535 )
          |||,
          message: 'Fehler: Jeder gesetzte runAsGroup auf Container-Ebene muss größer als 65535 sein.',
        },
        {
          expression: |||
            !(has(variables.podSpec.securityContext.runAsGroup)) ||
            !(has(variables.podSpec.securityContext)) ||
            variables.podSpec.securityContext.runAsGroup > 65535 ||
            variables.containers.all(c,
              has(c.securityContext) &&
              has(c.securityContext.runAsGroup) &&
              c.securityContext.runAsGroup > 65535)
          |||,
          message: 'Fehler: Pod-Ebene runAsGroup ≤ 65535 muss von allen Containern überschrieben werden.',
        },
        {
          expression: 'variables.podSpec.?securityContext.?supplementalGroups.orValue([]).all(group, group > 65535)',
          message: 'supplementalGroups: Alle GIDs müssen größer als 65535 sein (oder unset).',
        },
        {
          expression: 'variables.podSpec.?securityContext.?fsGroup.orValue(65536) > 65535',
          message: 'fsGroup muss größer als 65535 sein (oder unset).',
        },
      ],
    }),

    '019-disallow-default-serviceaccount': $.policy('019', 'disallow-default-serviceaccount', {
      bsi: { requirement: 'SYS.1.6.A5', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar],
      action: 'Deny',
      validations: [{
        expression: "variables.podSpec.?serviceAccountName.orValue('default') != 'default'",
        message: 'serviceAccountName must be set to anything other than "default".',
      }],
    }),

    '020-restrict-sa-automount-sa-token': $.policy('020', 'restrict-sa-automount-sa-token', {
      bsi: { requirement: 'SYS.1.6.A5', protection: 'standard', category: 'should' },
      resourceRules: [
        { apiGroups: [''], apiVersions: ['v1'], operations: writeOps, resources: ['serviceaccounts', 'pods'] },
        { apiGroups: ['apps'], apiVersions: ['v1'], operations: writeOps, resources: ['deployments', 'daemonsets', 'statefulsets'] },
        { apiGroups: ['batch'], apiVersions: ['v1'], operations: writeOps, resources: ['jobs', 'cronjobs'] },
      ],
      variables: [{
        // A ServiceAccount carries the field at its top level; the pod kinds carry
        // it in the (shape-located) pod spec.
        name: 'objectSpec',
        expression: |||
          has(object.spec) ?
            (has(object.spec.jobTemplate) ? object.spec.jobTemplate.spec.template.spec :
             has(object.spec.template) ? object.spec.template.spec :
             object.spec)
            : object
        |||,
      }],
      action: 'Audit',
      validations: [{
        expression: 'variables.objectSpec.?automountServiceAccountToken.orValue(true) == false',
        message: 'Must include automountServiceAccountToken to false.',
      }],
    }),

    '026-restrict-apparmor': $.policy('026', 'restrict-apparmor', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'should' },
      variables: [
        {
          name: 'podAnnotations',
          expression: |||
            has(object.spec.jobTemplate) ? object.spec.jobTemplate.spec.template.?metadata.?annotations.orValue({}) :
            has(object.spec.template) ? object.spec.template.?metadata.?annotations.orValue({}) :
            object.?metadata.?annotations.orValue({})
          |||,
        },
        $.podSpecVar,
        $.containersVar,
      ],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.podAnnotations.size() == 0 ||
          variables.containers.all(c,
            variables.podAnnotations["container.apparmor.security.beta.kubernetes.io/" + c.name].orValue('') == "runtime/default" ||
            variables.podAnnotations["container.apparmor.security.beta.kubernetes.io/" + c.name].orValue('').startsWith("localhost/")
          )
        |||,
        message: 'Specifying other AppArmor profiles is disallowed. The annotation `container.apparmor.security.beta.kubernetes.io/<container>` if defined must not be set to anything other than `runtime/default` or `localhost/*`.',
      }],
    }),

    '027-restrict-kernel-access': $.policy('027', 'restrict-kernel-access', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'must' },
      variables: [
        $.podSpecVar,
        $.containersVar,
        { name: 'allowedProfileTypes', expression: "['RuntimeDefault', 'Localhost']" },
        { name: 'allowedSysctls', expression: "['kernel.shm_rmid_forced','net.ipv4.ip_local_port_range','net.ipv4.ip_unprivileged_port_start','net.ipv4.tcp_syncookies','net.ipv4.ping_group_range']" },
      ],
      action: 'Audit',
      validations: [
        {
          expression: |||
            (
              variables.podSpec.?securityContext.?seccompProfile.?type.orValue('Localhost')
              in variables.allowedProfileTypes
            ) && (
              variables.containers.all(container,
                container.?securityContext.?seccompProfile.?type.orValue('Localhost')
                in variables.allowedProfileTypes
              )
            )
          |||,
          message: 'Use of custom Seccomp profiles is disallowed. The field spec.containers[*].securityContext.seccompProfile.type must be unset or set to `RuntimeDefault` or `Localhost`.',
        },
        {
          expression: "variables.containers.all(container, container.?securityContext.?procMount.orValue('Default') == 'Default')",
          message: 'Changing the proc mount from the default is not allowed.',
        },
        {
          expression: |||
            variables.containers.all(container, container.?securityContext.?sysctls.orValue([]).all(sysctl, sysctl == '' ||
              has(sysctl.name) && sysctl.name in variables.allowedSysctls))
          |||,
          message: 'Setting additional sysctls above the allowed type is disallowed. The field spec.securityContext.sysctls must be unset or not use any other names than kernel.shm_rmid_forced, net.ipv4.ip_local_port_range, net.ipv4.ip_unprivileged_port_start, net.ipv4.tcp_syncookies and net.ipv4.ping_group_range.',
        },
      ],
    }),

    '029-require-probes': $.policy('029', 'require-probes', {
      bsi: { requirement: 'SYS.1.6.A15', protection: 'standard', category: 'should' },
      variables: [$.podSpecVar, $.containersNoInitVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container,
            has(container.livenessProbe) ||
            has(container.startupProbe) ||
            has(container.readinessProbe) )
        |||,
        message: 'Liveness, readiness, or startup probes are required for all containers.',
      }],
    }),

    '101-disallow-host-ports': $.policy('101', 'disallow-host-ports', {
      bsi: { requirement: 'APP.4.4.A9', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar, $.containersVar],
      action: 'Audit',
      validations: [{
        expression: |||
          variables.containers.all(container, !has(container.ports) ||
            container.ports.all(port, !has(port.hostPort) || port.hostPort == 0))
        |||,
        message: 'Use of host ports is disallowed. The field spec.containers[*].ports[*].hostPort must either be unset or set to `0`.',
      }],
    }),

    '102-disallow-host-namespaces': $.policy('102', 'disallow-host-namespaces', {
      bsi: { requirement: 'APP.4.4.A9', protection: 'standard', category: 'must' },
      variables: [$.podSpecVar],
      action: 'Audit',
      validations: [{
        expression: '( variables.podSpec.?hostNetwork.orValue(false) == false) && ( variables.podSpec.?hostIPC.orValue(false) == false) && ( variables.podSpec.?hostPID.orValue(false) == false)',
        message: 'Sharing the host namespaces is disallowed. The fields spec.hostNetwork, spec.hostIPC, and spec.hostPID must be unset or set to `false`.',
      }],
    }),

    '126-disallow-selinux': $.policy('126', 'disallow-selinux', {
      bsi: { requirement: 'SYS.1.6.A17', protection: 'standard', category: 'should' },
      variables: [
        $.podSpecVar,
        $.containersVar,
        { name: 'seLinuxTypes', expression: "['container_t', 'container_init_t', 'container_kvm_t']" },
      ],
      action: 'Audit',
      validations: [
        {
          expression: |||
            (
              !has(variables.podSpec.securityContext) ||
              !has(variables.podSpec.securityContext.seLinuxOptions) ||
              !has(variables.podSpec.securityContext.seLinuxOptions.type) ||
              variables.seLinuxTypes.exists(type, type == variables.podSpec.securityContext.seLinuxOptions.type)
            ) && variables.containers.all(container,
              !has(container.securityContext) ||
              !has(container.securityContext.seLinuxOptions) ||
              !has(container.securityContext.seLinuxOptions.type) ||
              variables.seLinuxTypes.exists(type, type == container.securityContext.seLinuxOptions.type)
            )
          |||,
          message: 'Setting the SELinux type is restricted. The field securityContext.seLinuxOptions.type must either be unset or set to one of the allowed values (container_t, container_init_t, or container_kvm_t).',
        },
        {
          expression: |||
            (
              !has(variables.podSpec.securityContext) ||
              !has(variables.podSpec.securityContext.seLinuxOptions) ||
              (
                !has(variables.podSpec.securityContext.seLinuxOptions.user) &&
                !has(variables.podSpec.securityContext.seLinuxOptions.role)
              )
            ) &&
            variables.containers.all(container,
              !has(container.securityContext) ||
              !has(container.securityContext.seLinuxOptions) ||
              (
                !has(container.securityContext.seLinuxOptions.user) &&
                !has(container.securityContext.seLinuxOptions.role)
              )
            )
          |||,
          message: 'Setting the SELinux user or role is forbidden. The fields seLinuxOptions.user and seLinuxOptions.role must be unset.',
        },
      ],
    }),

    // The source (130) is a legacy Kyverno anyPattern on NetworkPolicy ingress
    // ports; rendered here as the equivalent CEL intent — no ingress rule may open
    // a remote-access port (SSH 22, Telnet 23, RDP 3389, VNC 5900).
    '130-disallow-remote-access-ports': $.policy('130', 'disallow-remote-access-ports', {
      bsi: { requirement: 'APP.4.4.A9', protection: 'standard', category: 'should' },
      resourceRules: [{ apiGroups: ['networking.k8s.io'], apiVersions: ['v1'], operations: writeOps, resources: ['networkpolicies'] }],
      variables: [{ name: 'remoteAccessPorts', expression: '[22, 23, 3389, 5900]' }],
      action: 'Audit',
      validations: [{
        expression: |||
          object.spec.?ingress.orValue([]).all(rule,
            rule.?ports.orValue([]).all(port,
              !has(port.port) || type(port.port) != int || !(port.port in variables.remoteAccessPorts)))
        |||,
        message: 'Remote access protocol ports (SSH 22, Telnet 23, RDP 3389, VNC 5900) must not be opened by a NetworkPolicy ingress rule.',
      }],
    }),

    '501-restrict-service-external-ips': $.policy('501', 'restrict-service-external-ips', {
      bsi: { requirement: 'APP.4.4.A9', protection: 'standard', category: 'must' },
      resourceRules: [{ apiGroups: [''], apiVersions: ['v1'], operations: writeOps, resources: ['services'] }],
      action: 'Audit',
      validations: [{
        expression: '!has(object.spec.externalIPs) || object.spec.externalIPs == null',
        message: 'externalIPs are not allowed.',
      }],
    }),
  },

  // Every policy and binding as a single kind: List, ready for kubectl apply.
  list:: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.flattenArrays([$.policies[name] for name in std.objectFields($.policies)]),
  },
}
