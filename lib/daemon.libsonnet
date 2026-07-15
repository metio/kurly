// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// daemon: a per-node agent — a DaemonSet with no Service and no ports.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

function(name, image)
  base.core(name, image)
  + {
    daemonset:
      local cfg = self.config;
      local podSpec = self.podSecurity + self.podVolumes + self.podScheduling + self.podExtras;
      k.apps.v1.daemonSet.new(cfg.name, [self.container], self.selectorLabels)
      + k.apps.v1.daemonSet.metadata.withLabels(self.labels)
      + k.apps.v1.daemonSet.spec.template.metadata.withLabelsMixin(self.podTemplateLabels)
      + { spec+: { template+: { spec+: podSpec } } }
      + (if cfg.annotations == {} then {} else k.apps.v1.daemonSet.metadata.withAnnotations(cfg.annotations))
      + (
        if self.podTemplateAnnotations == {}
        then {}
        else k.apps.v1.daemonSet.spec.template.metadata.withAnnotations(self.podTemplateAnnotations)
      ),
  }
