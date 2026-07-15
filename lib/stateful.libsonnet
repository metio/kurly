// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// stateful: a workload with stable identity and per-pod storage — a StatefulSet
// plus the headless Service that gives each replica a stable DNS name. The store
// feature renders as a per-pod volumeClaimTemplate here (each replica gets its
// own PersistentVolumeClaim), not the single shared PVC the Deployment kinds
// use, so scaling out provisions storage per replica.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

local headlessName(name) = name + '-headless';

function(name, image)
  base.core(name, image)
  + {
    local this = self,
    config+:: { replicas: 1 },

    // The store's storage is per-pod via volumeClaimTemplates, so there is no
    // single owned PVC to place — drop it.
    storeClaim:: null,

    statefulset:
      local cfg = self.config;
      // Captured before the nested literals below, where `self` would rebind.
      local container = self.container;
      // The store's volume is supplied by the template; keep every other volume.
      local nonStoreVolumes = [v for v in self.volumes if v.name != 'store'];
      local podSpec =
        self.podSecurity
        + (if nonStoreVolumes == [] then {} else { volumes: nonStoreVolumes })
        + self.podScheduling
        + self.podExtras
        + { containers: [container] };
      local volumeClaimTemplates =
        if cfg.store == null then []
        else [{
          metadata: { name: 'store' },
          spec: std.prune({
            accessModes: cfg.store.accessModes,
            resources: { requests: { storage: cfg.store.size } },
            storageClassName: cfg.store.storageClass,
            selector: (if cfg.store.selector == {} then null else cfg.store.selector),
          }),
        }];
      k.apps.v1.statefulSet.new(cfg.name)
      + k.apps.v1.statefulSet.metadata.withLabels(self.labels)
      + k.apps.v1.statefulSet.spec.withReplicas(cfg.replicas)
      + k.apps.v1.statefulSet.spec.withServiceName(headlessName(cfg.name))
      + k.apps.v1.statefulSet.spec.selector.withMatchLabels(self.selectorLabels)
      + { spec+: { volumeClaimTemplates: volumeClaimTemplates } }
      + k.apps.v1.statefulSet.spec.template.metadata.withLabels(self.podTemplateLabels)
      + { spec+: { template+: { spec: podSpec } } }
      + (if cfg.annotations == {} then {} else k.apps.v1.statefulSet.metadata.withAnnotations(cfg.annotations))
      + (
        if self.podTemplateAnnotations == {}
        then {}
        else k.apps.v1.statefulSet.spec.template.metadata.withAnnotations(self.podTemplateAnnotations)
      ),

    // The headless Service (clusterIP: None) the StatefulSet names, giving each
    // pod a stable <pod>.<service> DNS record. It carries the http port when the
    // workload declares one.
    service:
      local cfg = self.config;
      k.core.v1.service.new(
        headlessName(cfg.name),
        self.selectorLabels,
        if cfg.port == null then [] else [k.core.v1.servicePort.newNamed('http', 80, 'http')],
      )
      + k.core.v1.service.metadata.withLabels(self.labels)
      + k.core.v1.service.spec.withClusterIP('None'),
  }
