// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The shared core of every kurly workload: a hidden config object, computed
// labels/container values that late-bind against that config, and the fluent
// with* modifiers. Each workload kind composes this with its own manifest
// fields — the visible fields of the resulting object ARE the manifests.
local k = import './k.libsonnet';

{
  // core carries everything common to all workload kinds.
  core(name, image):: {
    // Late-bound handle on the composed app object, for fields whose value is
    // a nested object literal (where a bare `self` would bind to the literal).
    local this = self,

    config:: {
      name: name,
      image: image,
      port: null,
      env: {},
      labels: {},
      annotations: {},
      resources: { requests: { cpu: '100m', memory: '128Mi' } },
      serviceAccountName: null,
      probePath: null,
      // Pod Security Standards `restricted` defaults. Each has an explicit
      // escape hatch below for the workloads that genuinely need more.
      runAsNonRoot: true,
      readOnlyRootFilesystem: true,
      hostUsers: false,
    },

    // Selector labels feed immutable matchLabels fields, so they stay minimal
    // and stable — user labels must never leak in here.
    selectorLabels:: { 'app.kubernetes.io/name': this.config.name },

    labels:: self.selectorLabels {
      'app.kubernetes.io/managed-by': 'kurly',
    } + self.config.labels,

    // The pod-level half of the Pod Security Standards `restricted` profile;
    // each workload kind merges this into its pod template spec. The
    // container-level half lives in `container`. hostUsers=false runs the pod
    // in its own user namespace, so even a container-breakout lands in an
    // unprivileged host user. The ServiceAccount token is only mounted when a
    // ServiceAccount is explicitly configured — workloads that never talk to
    // the apiserver should not carry credentials for it.
    podSecurity:: {
      securityContext: {
        runAsNonRoot: this.config.runAsNonRoot,
        seccompProfile: { type: 'RuntimeDefault' },
      },
      automountServiceAccountToken: this.config.serviceAccountName != null,
    } + (if this.config.hostUsers then {} else { hostUsers: false }),

    container::
      local cfg = self.config;
      k.core.v1.container.new(cfg.name, cfg.image)
      + (
        if cfg.port == null
        then {}
        else k.core.v1.container.withPorts([k.core.v1.containerPort.newNamed(cfg.port, 'http')])
      )
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
        if cfg.probePath == null
        then {}
        else
          k.core.v1.container.readinessProbe.httpGet.withPath(cfg.probePath)
          + k.core.v1.container.readinessProbe.httpGet.withPort('http')
          + k.core.v1.container.livenessProbe.httpGet.withPath(cfg.probePath)
          + k.core.v1.container.livenessProbe.httpGet.withPort('http')
      )
      + k.core.v1.container.securityContext.withAllowPrivilegeEscalation(false)
      + k.core.v1.container.securityContext.withReadOnlyRootFilesystem(cfg.readOnlyRootFilesystem)
      + k.core.v1.container.securityContext.capabilities.withDrop(['ALL']),

    withImage(image):: self + { config+:: { image: image } },
    withPort(port):: self + { config+:: { port: port } },
    withEnv(env):: self + { config+:: { env+: env } },
    withLabels(labels):: self + { config+:: { labels+: labels } },
    withAnnotations(annotations):: self + { config+:: { annotations+: annotations } },
    withResources(requests=null, limits=null):: self + {
      config+:: {
        resources+:
          (if requests == null then {} else { requests: requests })
          + (if limits == null then {} else { limits: limits }),
      },
    },
    withServiceAccount(serviceAccountName):: self + { config+:: { serviceAccountName: serviceAccountName } },
    withHttpProbes(path='/healthz'):: self + { config+:: { probePath: path } },

    // Security escape hatches. Each one downgrades a single `restricted`
    // default for the workloads that genuinely need it — the rest of the
    // profile stays intact.
    withRootUser():: self + { config+:: { runAsNonRoot: false } },
    withWritableRootFilesystem():: self + { config+:: { readOnlyRootFilesystem: false } },
    withHostUsers():: self + { config+:: { hostUsers: true } },
  },

  // deployment adds the Deployment manifest plus replica control. Composed
  // onto core by every Deployment-backed kind (web, api, worker).
  deployment:: {
    config+:: { replicas: 1 },

    withReplicas(replicas):: self + { config+:: { replicas: replicas } },

    deployment:
      local cfg = self.config;
      local podSecurity = self.podSecurity;
      k.apps.v1.deployment.new(cfg.name, replicas=cfg.replicas, containers=[self.container], podLabels=self.selectorLabels)
      + k.apps.v1.deployment.metadata.withLabels(self.labels)
      + k.apps.v1.deployment.spec.template.metadata.withLabelsMixin(self.labels)
      + { spec+: { template+: { spec+: podSecurity } } }
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
  // container port. Composed onto core by the HTTP-facing kinds (web, api).
  service:: {
    service:
      local cfg = self.config;
      k.core.v1.service.new(cfg.name, self.selectorLabels, [k.core.v1.servicePort.newNamed('http', 80, 'http')])
      + k.core.v1.service.metadata.withLabels(self.labels),
  },
}
