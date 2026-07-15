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
      local podSecurity = self.podSecurity;
      local podVolumes = self.podVolumes;
      k.apps.v1.daemonSet.new(cfg.name, [self.container], self.selectorLabels)
      + k.apps.v1.daemonSet.metadata.withLabels(self.labels)
      + k.apps.v1.daemonSet.spec.template.metadata.withLabelsMixin(self.labels)
      + { spec+: { template+: { spec+: podSecurity + podVolumes } } }
      + (
        if cfg.annotations == {}
        then {}
        else
          k.apps.v1.daemonSet.metadata.withAnnotations(cfg.annotations)
          + k.apps.v1.daemonSet.spec.template.metadata.withAnnotations(cfg.annotations)
      )
      + (
        if cfg.serviceAccountName == null
        then {}
        else k.apps.v1.daemonSet.spec.template.spec.withServiceAccountName(cfg.serviceAccountName)
      ),
  }
