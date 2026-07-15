// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// job: a one-off task that runs to completion — a Job with restartPolicy
// OnFailure (a failed container is retried, not left dead). No Service, no
// replicas; the same hardened pod template as every other kind.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

function(name, image)
  base.core(name, image)
  + {
    job:
      local cfg = self.config;
      // Captured before the nested literal below, where `self` would rebind.
      local container = self.container;
      local podSpec =
        self.podSecurity
        + self.podVolumes
        + self.podScheduling
        + self.podExtras
        + { containers: [container], restartPolicy: 'OnFailure' };
      k.batch.v1.job.new(cfg.name)
      + k.batch.v1.job.metadata.withLabels(self.labels)
      + k.batch.v1.job.spec.template.metadata.withLabels(self.podTemplateLabels)
      + { spec+: { template+: { spec: podSpec } } }
      + (if cfg.annotations == {} then {} else k.batch.v1.job.metadata.withAnnotations(cfg.annotations))
      + (
        if self.podTemplateAnnotations == {}
        then {}
        else k.batch.v1.job.spec.template.metadata.withAnnotations(self.podTemplateAnnotations)
      ),
  }
