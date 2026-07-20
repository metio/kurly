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

    // The stores' storage is per-pod via volumeClaimTemplates, so there is no
    // single owned PVC to place — drop both handles.
    storeClaim:: null,
    storeClaims:: [],

    statefulset:
      local cfg = self.config;
      // Captured before the nested literals below, where `self` would rebind.
      local containers = self.podContainers;
      // The stores' volumes are supplied by the templates; keep every other volume
      // (config, secrets, scratch — none of which are PVC-backed).
      local nonStoreVolumes = [v for v in self.volumes if !std.objectHas(v, 'persistentVolumeClaim')];
      local podSpec =
        self.podSecurity
        + (if nonStoreVolumes == [] then {} else { volumes: nonStoreVolumes })
        + self.podScheduling
        + self.podExtras
        + { containers: containers };
      // The first store keeps the historical template name 'store'; additional
      // stores are named after their mount path, matching the pod's mount names.
      local storeVol(i, s) = if i == 0 then 'store' else base.volumeName(s.mountPath);
      local volumeClaimTemplates = [
        {
          // Annotations reach the claim here exactly as they do on the Deployment
          // path: several CSI drivers take their configuration through PVC
          // annotations alone, so losing them provisions a different volume
          // rather than the same one with less decoration.
          //
          // Labels are deliberately NOT added, unlike the Deployment path. A
          // StatefulSet's volumeClaimTemplates are immutable, so emitting labels
          // would change the template of every stateful workload already running
          // and make the next `kubectl apply` fail — a breaking change bought
          // for decoration. Annotations only change the template of a consumer
          // who asked for them, and who is getting nothing today.
          metadata: { name: storeVol(i, cfg.stores[i]) } + base.storeAnnotations(cfg.stores[i]),
          spec: std.prune({
            accessModes: cfg.stores[i].accessModes,
            resources: { requests: { storage: cfg.stores[i].size } },
            storageClassName: cfg.stores[i].storageClass,
            selector: (if cfg.stores[i].selector == {} then null else cfg.stores[i].selector),
          }),
        }
        for i in std.range(0, std.length(cfg.stores) - 1)
      ];
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
      // Captured out here: inside the object literal below, `self` would bind to
      // that literal rather than to the app.
      local ipFamilies = self.ipFamilySpec;
      k.core.v1.service.new(
        headlessName(cfg.name),
        self.selectorLabels,
        if cfg.port == null then [] else [k.core.v1.servicePort.newNamed('http', 80, 'http')],
      )
      + k.core.v1.service.metadata.withLabels(self.labels)
      + k.core.v1.service.spec.withClusterIP('None')
      // Every Service kurly renders agrees on its IP families, or a dual-stack
      // consumer fixes one and silently keeps the cluster's default on the rest.
      + { spec+: ipFamilies },
  }
